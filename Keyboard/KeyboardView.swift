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

// MARK: - Top bar: favorite languages, ★ to edit them, undo, Translate

struct TopBarView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
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
                .padding(.leading, 8)
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
                                    .background(Capsule().fill(selected ? Color.accentColor : Color(UIColor.keyLetter)))
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { model.editingFavorites = true } label: {
                            Image(systemName: "star")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 30)
                                .background(Capsule().fill(Color(UIColor.keySpecial)))
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose languages")
                    }
                    .padding(.horizontal, 5)
                }
            }

            if model.canUndo {
                Button(action: model.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.keySpecial)))
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
            .padding(.trailing, 5)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Pick which languages appear on the keyboard (opened with ★)

struct FavoritesEditorView: View {
    @ObservedObject var model: KeyboardModel
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Languages on keyboard").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Done") { model.editingFavorites = false }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                    .foregroundStyle(Color.white)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Languages.all) { language in
                        let on = model.languages.contains(language)
                        Button { model.toggleFavorite(language) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: on ? "star.fill" : "star")
                                    .foregroundStyle(on ? Color.yellow : Color.secondary)
                                Text(language.name).lineLimit(1).minimumScaleFactor(0.75)
                            }
                            .font(.footnote)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(Color(on ? UIColor.keyLetter : UIColor.keySpecial)))
                            .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .background(Color(UIColor.keyboardBackdrop))
    }
}
