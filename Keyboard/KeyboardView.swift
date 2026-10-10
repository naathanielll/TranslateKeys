import SwiftUI
import UIKit

// Colors that match Apple's keyboard in light and dark mode.
extension UIColor {
    static let keyLetter = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.42, alpha: 1) : .white }
    static let keySpecial = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) }
    static let keyShadow = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0, alpha: 0.55) : UIColor(red: 0.53, green: 0.54, blue: 0.56, alpha: 1) }
    static let keyboardBackdrop = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1) }
}

extension TargetLanguage {
    /// Short label for the language button, e.g. "ES".
    var short: String {
        switch code {
        case "zh-Hans": return "中文"
        case "zh-Hant": return "繁體"
        default: return String(code.prefix(2)).uppercased()
        }
    }
}

// MARK: - Top bar: language button · suggestions · undo · Translate

struct TopBarView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 6) {
            // Current language; tap to switch or edit favorites
            Button { model.pickingLanguage = true } label: {
                HStack(spacing: 3) {
                    Text(model.target.short).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.keyLetter)))
                .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Language: \(model.target.name). Tap to change.")

            middle
                .frame(maxWidth: .infinity)

            if model.canUndo {
                Button(action: model.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.keySpecial)))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo translation")
            }

            Button(action: model.translate) {
                HStack(spacing: 4) {
                    Image(systemName: "character.bubble")
                    Text("Translate").fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                .foregroundStyle(Color.white)
                .opacity(model.busy ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var middle: some View {
        if model.busy || !model.message.isEmpty {
            HStack(spacing: 6) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.busy ? "Translating to \(model.target.name)…" : model.message)
                    .font(.footnote)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.dismissMessage() }
        } else if !model.suggestions.isEmpty {
            // Apple-style suggestion strip
            HStack(spacing: 0) {
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1, height: 22)
                    }
                    Button { model.pick(item) } label: {
                        Text(item.text)
                            .font(.system(size: 16, weight: item.role == .correction ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(item.role == .correction ? Color(UIColor.keyLetter) : Color.clear)
                            )
                            .foregroundStyle(Color.primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            Text("Translate to \(model.target.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Language picker (tap a favorite to use it; Edit to star languages)

struct LanguagePickerView: View {
    @ObservedObject var model: KeyboardModel
    @State private var editing = false
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(editing ? "Star languages for the keyboard" : "Translate to")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(editing ? "Done" : "Edit") { editing.toggle() }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.keySpecial)))
                    .foregroundStyle(Color.primary)
                    .buttonStyle(.plain)
                Button { editing = false; model.pickingLanguage = false } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.keySpecial)))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(editing ? Languages.all : model.languages) { language in
                        if editing {
                            let on = model.languages.contains(language)
                            Button { model.toggleFavorite(language) } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: on ? "star.fill" : "star")
                                        .foregroundStyle(on ? Color.yellow : Color.secondary)
                                    Text(language.name).lineLimit(1).minimumScaleFactor(0.75)
                                }
                                .font(.footnote)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(on ? UIColor.keyLetter : UIColor.keySpecial)))
                                .foregroundStyle(Color.primary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            let selected = language.code == model.targetCode
                            Button {
                                model.choose(language)
                                model.pickingLanguage = false
                            } label: {
                                Text(language.name)
                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(RoundedRectangle(cornerRadius: 8)
                                        .fill(selected ? Color.accentColor : Color(UIColor.keyLetter)))
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .background(Color(UIColor.keyboardBackdrop))
    }
}
