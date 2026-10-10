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

    var body: some View {
        NavigationStack {
            Form {
                Section("Turn on the keyboard") {
                    Text("1. Download the languages you want below.")
                    Text("2. Settings → General → Keyboard → Keyboards → Add New Keyboard → TranslateKeys")
                    Text("3. Tap TranslateKeys there and turn on **Allow Full Access**.")
                    Text("4. In any app, type your message, tap 🌐, pick a language, tap **Translate**.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section {
                    ForEach(Languages.all.filter { $0.code != "en" }) { language in
                        HStack {
                            Text(language.name)
                            Spacer()
                            statusView(for: language)
                        }
                    }
                } header: {
                    Text("Languages (free, works offline)")
                } footer: {
                    Text("Each download pairs the language with English so you can translate both ways.")
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
