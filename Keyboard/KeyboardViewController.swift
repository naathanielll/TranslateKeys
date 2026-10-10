import UIKit
import SwiftUI
import Combine

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var topBar: UIHostingController<TopBarView>!
    private var picker: UIHostingController<LanguagePickerView>!
    private var keysView: KeysView!
    private var bag = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()

        model.proxyProvider = { [weak self] in self?.textDocumentProxy }
        model.nextKeyboard = { [weak self] in self?.advanceToNextInputMode() }

        // Language, suggestions, Translate (SwiftUI)
        topBar = UIHostingController(rootView: TopBarView(model: model))
        topBar.view.backgroundColor = .clear
        // Keys (UIKit, for low-latency typing)
        keysView = KeysView(model: model)
        // Language picker shown over the keys
        picker = UIHostingController(rootView: LanguagePickerView(model: model))
        picker.view.backgroundColor = .clear
        picker.view.isHidden = true

        let children: [UIViewController] = [topBar, picker]
        children.forEach { addChild($0) }
        let subviews: [UIView] = [topBar.view, keysView, picker.view]
        for sub in subviews {
            sub.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sub)
        }
        topBar.didMove(toParent: self)
        picker.didMove(toParent: self)
        view.bringSubviewToFront(keysView)      // key pop-ups draw over the top bar
        view.bringSubviewToFront(picker.view)

        let height = view.heightAnchor.constraint(equalToConstant: KeysView.preferredHeight + 46)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            topBar.view.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.view.heightAnchor.constraint(equalToConstant: 46),

            keysView.topAnchor.constraint(equalTo: topBar.view.bottomAnchor),
            keysView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keysView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keysView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            picker.view.topAnchor.constraint(equalTo: view.topAnchor),
            picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height
        ])

        model.$pickingLanguage
            .receive(on: RunLoop.main)
            .sink { [weak self] open in self?.picker.view.isHidden = !open }
            .store(in: &bag)

        // Names from your contacts and text replacements, so autocorrect leaves them alone.
        requestSupplementaryLexicon { [weak self] lexicon in
            let entries = lexicon.entries
            DispatchQueue.main.async { self?.model.speller.setLexicon(entries) }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.reloadSettings()
        model.loadFavorites()
        model.refresh()
        keysView.reloadSettings()
        TranslatorEngine.shared.prewarm(to: model.target)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Phones with a home button need a 🌐 key on the keyboard; Face ID phones show it below.
        if model.showGlobe != needsInputModeSwitchKey { model.showGlobe = needsInputModeSwitchKey }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.refresh()
    }
}

enum KeyLayer { case letters, numbers, symbols }
enum ShiftState { case off, once, locked }

struct SuggestionItem: Identifiable, Equatable {
    enum Role { case keep, correction, completion }
    let text: String
    let role: Role
    var id: String { "\(role)-\(text)" }
}

@MainActor
final class KeyboardModel: ObservableObject {
    // Shown by the SwiftUI top bar. Only changes when something visible changes.
    @Published var targetCode: String = Prefs.lastTarget
    @Published var languages: [TargetLanguage] = SharedStore.favoriteLanguages
    @Published var pickingLanguage = false
    @Published var message = ""
    @Published var busy = false
    @Published var canUndo = false
    @Published var suggestions: [SuggestionItem] = []

    // Typing state goes straight to the keys (no SwiftUI redraw on every keystroke).
    var onLayoutChange: (() -> Void)?
    var onShiftChange: (() -> Void)?
    var layer: KeyLayer = .letters { didSet { if layer != oldValue { onLayoutChange?() } } }
    var shift: ShiftState = .once { didSet { if shift != oldValue { onShiftChange?() } } }
    var showGlobe = false { didSet { if showGlobe != oldValue { onLayoutChange?() } } }

    var hasFullAccess = true
    var proxyProvider: () -> UITextDocumentProxy? = { nil }
    var nextKeyboard: () -> Void = {}

    let speller = Speller()
    private var autocorrectOn = true
    private var currentWord = ""
    private var pendingCorrection: String?
    private var pendingFor = ""
    private var suggestionWork: DispatchWorkItem?
    private var skipCorrectionFor: String?
    private var lastCorrection: (original: String, corrected: String, separator: String)?

    private var task: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var lastOriginal = ""
    private var lastInserted = ""
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast

    var target: TargetLanguage { Languages.find(targetCode) }
    private var proxy: UITextDocumentProxy? { proxyProvider() }

    func reloadSettings() {
        autocorrectOn = SharedStore.autocorrect
        speller.setLanguage(fromCode: Prefs.lastSource)
    }

    private func clearUndo() { if canUndo { canUndo = false } }

    // MARK: Typing

    func type(_ key: String) {
        guard let proxy else { return }
        let text = (layer == .letters && shift != .off) ? key.uppercased() : key
        if ".,?!;:".contains(key) {
            finishWord(separator: text)        // autocorrect before punctuation
        } else {
            proxy.insertText(text)
            lastCorrection = nil
        }
        clearUndo()
        // Like Apple's keyboard: after an apostrophe on the number pad, go back to letters
        if layer != .letters && key == "'" { layer = .letters }
        afterChange()
    }

    func space() {
        guard let proxy else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        let now = Date()
        // Double-tap space for ". "
        if now.timeIntervalSince(lastSpaceTap) < 0.4, before.hasSuffix(" "),
           let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastCorrection = nil
        } else {
            finishWord(separator: " ")
        }
        lastSpaceTap = now
        clearUndo()
        if layer != .letters { layer = .letters }
        afterChange()
    }

    func newline() {
        finishWord(separator: "\n")
        clearUndo()
        afterChange()
    }

    func deleteBackward() {
        guard let proxy else { return }
        // Delete right after an autocorrect puts your original word back (and remembers it).
        if let fix = lastCorrection,
           (proxy.documentContextBeforeInput ?? "").hasSuffix(fix.corrected + fix.separator) {
            for _ in 0..<(fix.corrected.count + fix.separator.count) { proxy.deleteBackward() }
            proxy.insertText(fix.original)
            speller.learn(fix.original)
            skipCorrectionFor = fix.original
            lastCorrection = nil
        } else {
            proxy.deleteBackward()
            lastCorrection = nil
        }
        clearUndo()
        afterChange()
    }

    func moveCursor(by offset: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: offset)
        lastCorrection = nil
        afterChange()
    }

    func tapShift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3 {
            shift = .locked
        } else {
            shift = (shift == .off) ? .once : .off
        }
        lastShiftTap = now
    }

    func setLayer(_ newLayer: KeyLayer) {
        layer = newLayer
        afterChange()
    }

    func refresh() { afterChange() }

    // MARK: Autocorrect

    private var autocorrectAllowed: Bool {
        guard autocorrectOn, let proxy else { return false }
        if proxy.autocorrectionType == UITextAutocorrectionType.no { return false }
        let type = proxy.keyboardType ?? .default
        return ![.URL, .emailAddress, .webSearch, .twitter, .asciiCapableNumberPad, .numberPad, .phonePad]
            .contains(type)
    }

    /// End the current word: apply the pending correction, then add the separator.
    private func finishWord(separator: String) {
        guard let proxy else { return }
        let word = currentWord
        // Use the already-computed fix if it's for this word; otherwise check now.
        let fix: String? = word.isEmpty || word == skipCorrectionFor || !autocorrectAllowed ? nil
            : (pendingFor == word ? pendingCorrection : speller.correctionNow(for: word))
        if let fix {
            for _ in 0..<word.count { proxy.deleteBackward() }
            proxy.insertText(fix + separator)
            lastCorrection = (word, fix, separator)
        } else {
            proxy.insertText(separator)
            lastCorrection = nil
        }
        skipCorrectionFor = nil
    }

    /// Tap a word in the suggestion bar.
    func pick(_ item: SuggestionItem) {
        guard let proxy else { return }
        switch item.role {
        case .keep:
            speller.learn(currentWord)
            proxy.insertText(" ")
            lastCorrection = nil
        case .correction, .completion:
            for _ in 0..<currentWord.count { proxy.deleteBackward() }
            proxy.insertText(item.text + " ")
            lastCorrection = nil
        }
        skipCorrectionFor = nil
        clearUndo()
        if layer != .letters { layer = .letters }
        afterChange()
    }

    /// One read of the text before the cursor, then update shift, the current word and suggestions.
    private func afterChange() {
        let before = proxy?.documentContextBeforeInput ?? ""
        updateAutoShift(before)

        var chars: [Character] = []
        for c in before.reversed() {
            if c.isLetter || c == "'" || c == "’" { chars.append(c) } else { break }
        }
        currentWord = String(chars.reversed())

        // Spell-check in the background, only once you pause briefly, so fast typing never waits.
        suggestionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateSuggestions() }
        suggestionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
    }

    private func updateSuggestions() {
        let word = currentWord
        guard autocorrectAllowed, !word.isEmpty else {
            pendingCorrection = nil
            pendingFor = ""
            if !suggestions.isEmpty { suggestions = [] }
            return
        }
        let skip = word == skipCorrectionFor
        speller.suggest(for: word) { [weak self] fix, others in
            guard let self, self.currentWord == word else { return }   // you've typed more since
            let fix = skip ? nil : fix
            self.pendingCorrection = fix
            self.pendingFor = word
            var items: [SuggestionItem]
            if let fix {
                items = [SuggestionItem(text: "“\(word)”", role: .keep),
                         SuggestionItem(text: fix, role: .correction)]
                items += others.prefix(1).map { SuggestionItem(text: $0, role: .completion) }
            } else {
                items = others.map { SuggestionItem(text: $0, role: .completion) }
            }
            if items != self.suggestions { self.suggestions = items }
        }
    }

    /// Capitalize the first letter of a message or sentence.
    private func updateAutoShift(_ before: String) {
        guard shift != .locked, layer == .letters else { return }
        guard let proxy, proxy.autocapitalizationType != UITextAutocapitalizationType.none else {
            shift = .off
            return
        }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let startOfSentence = trimmed.isEmpty
            || (before.hasSuffix(" ") && ["." as Character, "!", "?"].contains(trimmed.last ?? " "))
            || before.hasSuffix("\n")
        shift = startOfSentence ? .once : .off
    }

    // MARK: Languages & favorites

    /// Reload favorites; keep the current choice if it's still a favorite.
    func loadFavorites() {
        let latest = SharedStore.favoriteLanguages
        if latest != languages { languages = latest }
        if !languages.contains(where: { $0.code == targetCode }), let first = languages.first {
            choose(first)
        }
    }

    func choose(_ language: TargetLanguage) {
        guard language.code != targetCode else { return }
        targetCode = language.code
        Prefs.lastTarget = language.code
        TranslatorEngine.shared.prewarm(to: language)
    }

    func toggleFavorite(_ language: TargetLanguage) {
        var codes = SharedStore.favorites
        if codes.contains(language.code) {
            guard codes.count > 1 else { return }   // keep at least one
            codes.removeAll { $0 == language.code }
        } else {
            codes.append(language.code)
        }
        SharedStore.favorites = codes
        loadFavorites()
    }

    // MARK: Messages

    private func flash(_ text: String, seconds: Double = 3) {
        message = text
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { message = "" }
        }
    }

    func dismissMessage() { messageTask?.cancel(); message = "" }

    // MARK: Translate

    /// Selected text if any, otherwise the text before the cursor.
    private func currentSource() -> (text: String, isSelection: Bool) {
        guard let proxy else { return ("", false) }
        if let selected = proxy.selectedText, !selected.isEmpty { return (selected, true) }
        return (proxy.documentContextBeforeInput ?? "", false)
    }

    /// Translate what you typed and replace it in the message box.
    func translate() {
        let source = currentSource()
        let original = source.text
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            flash("Type your message first, then tap Translate.")
            return
        }
        let leading = String(original.prefix(while: { $0.isWhitespace }))
        let trailing = String(original.reversed().prefix(while: { $0.isWhitespace }).reversed())

        task?.cancel()
        messageTask?.cancel()
        busy = true
        message = ""
        clearUndo()
        let target = self.target
        task = Task {
            do {
                let output = try await TranslatorEngine.shared.translate(trimmed, to: target)
                if !Task.isCancelled {
                    apply(leading + output + trailing, replacing: original,
                          isSelection: source.isSelection, targetName: target.name)
                }
            } catch {
                if !Task.isCancelled {
                    var text = error.localizedDescription
                    if !hasFullAccess {
                        text += " If this keeps happening, turn on Allow Full Access for TranslateKeys."
                    }
                    flash(text, seconds: 6)
                }
            }
            busy = false
            speller.setLanguage(fromCode: Prefs.lastSource)
        }
    }

    private func apply(_ translation: String, replacing original: String, isSelection: Bool, targetName: String) {
        guard let proxy else { return }
        let stillSelected = isSelection && (proxy.selectedText ?? "") == original
        if !stillSelected {
            guard (proxy.documentContextBeforeInput ?? "").hasSuffix(original) else {
                flash("The text changed while translating. Tap Translate again.")
                return
            }
            for _ in 0..<original.count { proxy.deleteBackward() }
        }
        proxy.insertText(translation)
        lastOriginal = original
        lastInserted = translation
        lastCorrection = nil
        canUndo = true
        flash("Translated to \(targetName). Tap ↩︎ to undo.")
        afterChange()
    }

    /// Put the original text back.
    func undo() {
        guard canUndo, let proxy,
              (proxy.documentContextBeforeInput ?? "").hasSuffix(lastInserted) else {
            clearUndo()
            return
        }
        for _ in 0..<lastInserted.count { proxy.deleteBackward() }
        proxy.insertText(lastOriginal)
        canUndo = false
        flash("Original restored.")
        afterChange()
    }
}
