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

        let height = host.view.heightAnchor.constraint(equalToConstant: 270)
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
        model.refresh()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.refresh()
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var targetCode: String = Prefs.lastTarget
    @Published var sourcePreview = ""
    @Published var message = ""
    @Published var busy = false
    @Published var canUndo = false
    var hasFullAccess = true

    var proxyProvider: () -> UITextDocumentProxy? = { nil }
    var nextKeyboard: () -> Void = {}

    private var task: Task<Void, Never>?
    private var lastOriginal = ""
    private var lastInserted = ""

    var target: TargetLanguage { Languages.find(targetCode) }

    /// Selected text if any, otherwise the text before the cursor.
    private func currentSource() -> (text: String, isSelection: Bool) {
        guard let proxy = proxyProvider() else { return ("", false) }
        if let selected = proxy.selectedText, !selected.isEmpty { return (selected, true) }
        return (proxy.documentContextBeforeInput ?? "", false)
    }

    func refresh() {
        sourcePreview = currentSource().text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func choose(_ language: TargetLanguage) {
        targetCode = language.code
        Prefs.lastTarget = language.code
    }

    /// Translate the typed (or selected) text and replace it in the message box.
    func translate() {
        let source = currentSource()
        let original = source.text
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "Type your message with your normal keyboard, then tap 🌐 to switch here."
            return
        }
        // Keep spaces/newlines around the text exactly as they were.
        let leading = String(original.prefix(while: { $0.isWhitespace }))
        let trailing = String(original.reversed().prefix(while: { $0.isWhitespace }).reversed())

        task?.cancel()
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
                        text += " If this keeps happening, turn on Allow Full Access for TranslateKeys in Settings."
                    }
                    message = text
                }
            }
            busy = false
        }
    }

    private func apply(_ translation: String, replacing original: String, isSelection: Bool, targetName: String) {
        guard let proxy = proxyProvider() else { return }
        let stillSelected = isSelection && (proxy.selectedText ?? "") == original
        if !stillSelected {
            // Only delete if the text before the cursor is still what we translated.
            guard (proxy.documentContextBeforeInput ?? "").hasSuffix(original) else {
                message = "The text changed while translating. Tap Translate again."
                return
            }
            for _ in 0..<original.count { proxy.deleteBackward() }
        }
        proxy.insertText(translation)
        lastOriginal = original
        lastInserted = translation
        canUndo = true
        message = "Translated to \(targetName)."
        refresh()
    }

    /// Put the original text back.
    func undo() {
        guard canUndo, let proxy = proxyProvider(),
              (proxy.documentContextBeforeInput ?? "").hasSuffix(lastInserted) else {
            canUndo = false
            return
        }
        for _ in 0..<lastInserted.count { proxy.deleteBackward() }
        proxy.insertText(lastOriginal)
        canUndo = false
        message = "Original restored."
        refresh()
    }

    func deleteBackward() { proxyProvider()?.deleteBackward(); canUndo = false; refresh() }
    func space() { proxyProvider()?.insertText(" "); canUndo = false; refresh() }
    func newline() { proxyProvider()?.insertText("\n"); canUndo = false; refresh() }
}
