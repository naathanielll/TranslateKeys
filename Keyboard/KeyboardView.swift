import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            languageRow
            statusCard
            controlRow
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    // Tap a language to choose what Translate turns your text into.
    private var languageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Languages.all) { language in
                    let selected = language.code == model.targetCode
                    Button(language.name) { model.choose(language) }
                        .font(.subheadline.weight(selected ? .bold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selected ? Color.accentColor : Color(.secondarySystemBackground)))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.sourcePreview.isEmpty ? "Nothing typed yet" : model.sourcePreview)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(model.sourcePreview.isEmpty ? .secondary : .primary)
            if model.busy {
                HStack(spacing: 8) { ProgressView(); Text("Translating to \(model.target.name)…").foregroundStyle(.secondary) }
                    .font(.footnote)
            } else if !model.message.isEmpty {
                Text(model.message).font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Translate replaces this with \(model.target.name).").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
    }

    private var controlRow: some View {
        HStack(spacing: 6) {
            key(systemImage: "globe") { model.nextKeyboard() }
            key(title: "space", flexible: true) { model.space() }
            key(systemImage: "delete.left") { model.deleteBackward() }
            if model.canUndo {
                key(systemImage: "arrow.uturn.backward") { model.undo() }
            } else {
                key(systemImage: "return") { model.newline() }
            }
            Button { model.translate() } label: {
                Text("Translate").bold().frame(minWidth: 96, minHeight: 42)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
            .foregroundStyle(.white)
            .disabled(model.busy)
        }
    }

    private func key(title: String? = nil, systemImage: String? = nil, flexible: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage { Image(systemName: systemImage) } else { Text(title ?? "") }
            }
            .frame(minWidth: 44, maxWidth: flexible ? .infinity : nil, minHeight: 42)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
        .foregroundStyle(Color.primary)
    }
}
