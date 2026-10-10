import SwiftUI
import UIKit

// MARK: - Key colors that match the system keyboard in light and dark mode
private extension Color {
    static let keyLetter = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.42, alpha: 1) : .white })
    static let keySpecial = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) })
    static let keyShadow = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0, alpha: 0.5) : UIColor(red: 0.53, green: 0.54, blue: 0.56, alpha: 1) })
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    private let spacing: CGFloat = 6
    private let rowSpacing: CGFloat = 11
    private let keyHeight: CGFloat = 43

    var body: some View {
        VStack(spacing: 8) {
            topBar
                .frame(height: 38)
            GeometryReader { geo in
                let unit = (geo.size.width - spacing * 9) / 10
                VStack(spacing: rowSpacing) {
                    charRow(rows.0, width: unit)
                    charRow(rows.1, width: unit)
                    HStack(spacing: spacing) {
                        leftModifierKey.frame(width: unit * 1.35)
                        Spacer(minLength: 0)
                        charRow(rows.2, width: model.layer == .letters ? unit : unit * 1.35)
                        Spacer(minLength: 0)
                        KeyButton(kind: .special, repeats: true, onPress: model.tap, action: model.deleteBackward) {
                            Image(systemName: "delete.left").font(.system(size: 19))
                        }
                        .frame(width: unit * 1.35)
                    }
                    .frame(height: keyHeight)
                    bottomRow(unit: unit)
                }
            }
            .frame(height: keyHeight * 4 + rowSpacing * 3)
        }
        .padding(.horizontal, 3)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: Top bar: languages, status, undo, Translate

    private var topBar: some View {
        HStack(spacing: 6) {
            if model.busy || !model.message.isEmpty {
                HStack(spacing: 8) {
                    if model.busy { ProgressView() }
                    Text(model.busy ? "Translating to \(model.target.name)…" : model.message)
                        .font(.footnote)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .contentShape(Rectangle())
                .onTapGesture { model.dismissMessage() }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.languages) { language in
                            let selected = language.code == model.targetCode
                            Button { model.choose(language) } label: {
                                Text(language.name)
                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(selected ? Color.accentColor : Color.keyLetter))
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 3)
                }
            }

            if model.canUndo {
                Button(action: model.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.keySpecial))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo translation")
            }

            Button(action: model.translate) {
                HStack(spacing: 5) {
                    Image(systemName: "character.bubble")
                    Text("Translate").fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                .foregroundStyle(Color.white)
                .opacity(model.busy ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
        }
    }

    // MARK: Key rows

    private var rows: ([String], [String], [String]) {
        switch model.layer {
        case .letters:
            return ("qwertyuiop".map(String.init), "asdfghjkl".map(String.init), "zxcvbnm".map(String.init))
        case .numbers:
            return ("1234567890".map(String.init),
                    ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
                    [".", ",", "?", "!", "'"])
        case .symbols:
            return (["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                    ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
                    [".", ",", "?", "!", "'"])
        }
    }

    private func charRow(_ keys: [String], width: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyButton(kind: .letter, onPress: model.tap, action: { model.type(key) }) {
                    Text(label(for: key))
                        .font(.system(size: model.layer == .letters ? 24 : 22))
                }
                .frame(width: width)
            }
        }
        .frame(height: keyHeight)
    }

    private func label(for key: String) -> String {
        model.layer == .letters && model.shift != .off ? key.uppercased() : key
    }

    @ViewBuilder
    private var leftModifierKey: some View {
        switch model.layer {
        case .letters:
            KeyButton(kind: model.shift == .off ? .special : .letter, onPress: model.tap, action: model.tapShift) {
                Image(systemName: model.shift == .locked ? "capslock.fill"
                      : model.shift == .once ? "shift.fill" : "shift")
                    .font(.system(size: 19))
            }
        case .numbers:
            KeyButton(kind: .special, onPress: model.tap, action: { model.layer = .symbols }) {
                Text("#+=").font(.system(size: 16))
            }
        case .symbols:
            KeyButton(kind: .special, onPress: model.tap, action: { model.layer = .numbers }) {
                Text("123").font(.system(size: 16))
            }
        }
    }

    private func bottomRow(unit: CGFloat) -> some View {
        HStack(spacing: spacing) {
            KeyButton(kind: .special, onPress: model.tap, action: {
                model.layer = model.layer == .letters ? .numbers : .letters
            }) {
                Text(model.layer == .letters ? "123" : "ABC").font(.system(size: 16))
            }
            .frame(width: unit * 1.3)

            if model.showGlobe {
                KeyButton(kind: .special, onPress: model.tap, action: model.nextKeyboard) {
                    Image(systemName: "globe").font(.system(size: 18))
                }
                .frame(width: unit * 1.1)
            }

            KeyButton(kind: .letter, onPress: model.tap, action: model.space) {
                Text("space").font(.system(size: 16))
            }

            KeyButton(kind: .special, onPress: model.tap, action: model.newline) {
                Text("return").font(.system(size: 16))
            }
            .frame(width: unit * 2.1)
        }
        .frame(height: keyHeight)
    }
}

// MARK: - A single key with a press state (and auto-repeat for delete)

struct KeyButton<Label: View>: View {
    enum Kind { case letter, special }

    var kind: Kind
    var repeats = false
    var onPress: () -> Void = {}
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var pressed = false
    @State private var repeatTimer: Timer?

    var body: some View {
        label()
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
                    .shadow(color: .keyShadow, radius: 0, x: 0, y: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onPress()
                        action()
                        if repeats { startRepeating() }
                    }
                    .onEnded { _ in
                        pressed = false
                        repeatTimer?.invalidate()
                        repeatTimer = nil
                    }
            )
            .accessibilityAddTraits(.isButton)
    }

    private var fill: Color {
        switch kind {
        case .letter: return pressed ? .keySpecial : .keyLetter
        case .special: return pressed ? .keyLetter : .keySpecial
        }
    }

    private func startRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                if pressed { action() }
            }
        }
    }
}
