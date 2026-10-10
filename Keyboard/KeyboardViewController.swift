import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        model.proxyProvider = { [weak self] in self?.textDocumentProxy }
        model.nextKeyboard = { [weak self] in self?.advanceToNextInputMode() }

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)

        let height = host.view.heightAnchor.constraint(equalToConstant: 286)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height
        ])
        host.didMove(toParent: self)
        self.host = host
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.loadFavorites()
        model.refresh()
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

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var targetCode: String = Prefs.lastTarget
    @Published var message = ""
    @Published var busy = false
    @Published var canUndo = false
    @Published var layer: KeyLayer = .letters
    @Published var shift: ShiftState = .once
    @Published var showGlobe = false
    @Published var languages: [TargetLanguage] = SharedStore.favoriteLanguages
    var hasFullAccess = true

    var proxyProvider: () -> UITextDocumentProxy? = { nil }
    var nextKeyboard: () -> Void = {}

    private var task: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var lastOriginal = ""
    private var lastInserted = ""
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var target: TargetLanguage { Languages.find(targetCode) }
    private var proxy: UITextDocumentProxy? { proxyProvider() }

    // MARK: Typing

    func tap() { haptic.impactOccurred(intensity: 0.6) }

    func type(_ key: String) {
        let text = (layer == .letters && shift != .off) ? key.uppercased() : key
        proxy?.insertText(text)
        canUndo = false
        // iOS-style: after an apostrophe on the number pad, go back to letters
        if layer != .letters && key == "'" { layer = .letters }
        updateAutoShift()
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
        } else {
            proxy.insertText(" ")
        }
        lastSpaceTap = now
        canUndo = false
        if layer != .letters { layer = .letters }
        updateAutoShift()
    }

    func deleteBackward() {
        proxy?.deleteBackward()
        canUndo = false
        updateAutoShift()
    }

    func newline() {
        proxy?.insertText("\n")
        canUndo = false
        updateAutoShift()
    }

    func tapShift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.35 {
            shift = .locked
        } else {
            shift = (shift == .off) ? .once : .off
        }
        lastShiftTap = now
    }

    func refresh() { updateAutoShift() }

    /// Capitalize the first letter of a message or sentence.
    private func updateAutoShift() {
        guard shift != .locked, layer == .letters else { return }
        guard let proxy, proxy.autocapitalizationType != UITextAutocapitalizationType.none else {
            shift = .off
            return
        }
        let before = proxy.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let startOfSentence = trimmed.isEmpty
            || (before.hasSuffix(" ") && ["." as Character, "!", "?"].contains(trimmed.last ?? " "))
            || before.hasSuffix("\n")
        shift = startOfSentence ? .once : .off
    }

    // MARK: Languages & messages

    /// Reload the favorites picked in the app; keep the current choice if it's still a favorite.
    func loadFavorites() {
        languages = SharedStore.favoriteLanguages
        if !languages.contains(where: { $0.code == targetCode }), let first = languages.first {
            choose(first)
        }
    }

    func choose(_ language: TargetLanguage) {
        targetCode = language.code
        Prefs.lastTarget = language.code
    }

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
        canUndo = false
        let target = self.target
        task = Task {
            do {
                let output = try await FreeTranslator.translate(trimmed, to: target)
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
        canUndo = true
        flash("Translated to \(targetName). Tap ↩︎ to undo.")
        updateAutoShift()
    }

    /// Put the original text back.
    func undo() {
        guard canUndo, let proxy,
              (proxy.documentContextBeforeInput ?? "").hasSuffix(lastInserted) else {
            canUndo = false
            return
        }
        for _ in 0..<lastInserted.count { proxy.deleteBackward() }
        proxy.insertText(lastOriginal)
        canUndo = false
        flash("Original restored.")
        updateAutoShift()
    }
}
