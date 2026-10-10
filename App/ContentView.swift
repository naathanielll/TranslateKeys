import SwiftUI
import Translation

struct ContentView: View {
    // Translation packs are downloaded as pairs with your own language.
    private let home = Locale.Language(identifier: "en")

    @State private var statuses: [String: LanguageAvailability.Status] = [:]
    @State private var downloadConfig: TranslationSession.Configuration?
    @State private var downloadingCode: String?
    @State private var testText = "Where is the nearest subway station?"
    @State private var testCode = "es"
    @State private var testResult = ""
    @State private var testing = false
    @State private var favorites: [String] = SharedStore.favorites

    var body: some View {
        NavigationStack {
            Form {
                Section("Turn on the keyboard") {
                    Text("1. Star the languages you want on the keyboard and tap Download for each.")
                    Text("2. Settings → General → Keyboard → Keyboards → Add New Keyboard → TranslateKeys")
                    Text("3. Tap TranslateKeys there and turn on **Allow Full Access**.")
                    Text("4. In any app, switch to TranslateKeys with 🌐, type your message, pick a language and tap **Translate**.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section {
                    ForEach(Languages.all) { language in
                        HStack(spacing: 12) {
                            Button { toggleFavorite(language) } label: {
                                Image(systemName: favorites.contains(language.code) ? "star.fill" : "star")
                                    .foregroundStyle(favorites.contains(language.code) ? Color.yellow : Color.secondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(favorites.contains(language.code)
                                                ? "Remove \(language.name) from keyboard"
                                                : "Show \(language.name) on keyboard")
                            Text(language.name)
                            Spacer()
                            if language.code == "en" {
                                Text("Built in").foregroundStyle(.secondary).font(.subheadline)
                            } else {
                                statusView(for: language)
                            }
                        }
                    }
                } header: {
                    Text("Languages")
                } footer: {
                    Text(SharedStore.isShared
                         ? "Starred languages appear on the keyboard. Downloads are free and work offline."
                         : "The keyboard couldn't connect to the app's settings, so it will show every language. Downloads are free and work offline.")
                }

                Section("Try it here") {
                    TextField("Text", text: $testText, axis: .vertical)
                    Picker("Into", selection: $testCode) {
                        ForEach(Languages.all) { Text($0.name).tag($0.code) }
                    }
                    Button(testing ? "Translating…" : "Translate") { runTest() }
                        .disabled(testing)
                    if !testResult.isEmpty {
                        Text(testResult).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("TranslateKeys")
            .task { await refreshStatuses() }
            .translationTask(downloadConfig) { session in
                // Shows Apple's download prompt for the language pair.
                do { try await session.prepareTranslation() } catch { }
                downloadingCode = nil
                await refreshStatuses()
            }
        }
    }

    @ViewBuilder
    private func statusView(for language: TargetLanguage) -> some View {
        switch statuses[language.code] {
        case .installed:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
                .font(.subheadline)
        case .supported:
            if downloadingCode == language.code {
                ProgressView()
            } else {
                Button("Download") { download(language) }
                    .buttonStyle(.borderless)
            }
        case .unsupported:
            Text("Not available").foregroundStyle(.secondary).font(.subheadline)
        default:
            ProgressView()
        }
    }

    private func toggleFavorite(_ language: TargetLanguage) {
        if favorites.contains(language.code) {
            guard favorites.count > 1 else { return }   // keep at least one language
            favorites.removeAll { $0 == language.code }
        } else {
            favorites.append(language.code)
        }
        SharedStore.favorites = favorites
    }

    private func download(_ language: TargetLanguage) {
        downloadingCode = language.code
        if downloadConfig?.target == language.language {
            downloadConfig?.invalidate()
        } else {
            downloadConfig = TranslationSession.Configuration(source: home, target: language.language)
        }
    }

    private func refreshStatuses() async {
        let availability = LanguageAvailability()
        var result: [String: LanguageAvailability.Status] = [:]
        for language in Languages.all where language.code != "en" {
            result[language.code] = await availability.status(from: home, to: language.language)
        }
        statuses = result
    }

    private func runTest() {
        testing = true
        testResult = ""
        let target = Languages.find(testCode)
        Task {
            do { testResult = try await FreeTranslator.translate(testText, to: target) }
            catch { testResult = error.localizedDescription }
            testing = false
        }
    }
}
