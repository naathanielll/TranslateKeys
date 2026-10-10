import Foundation
import NaturalLanguage
import Translation

// Languages Apple's built-in (free, on-device) translator supports.
struct TargetLanguage: Identifiable, Hashable {
    let name: String
    let code: String
    var id: String { code }
    var language: Locale.Language { Locale.Language(identifier: code) }
}

enum Languages {
    static let all: [TargetLanguage] = [
        TargetLanguage(name: "Spanish", code: "es"),
        TargetLanguage(name: "English", code: "en"),
        TargetLanguage(name: "French", code: "fr"),
        TargetLanguage(name: "Japanese", code: "ja"),
        TargetLanguage(name: "Korean", code: "ko"),
        TargetLanguage(name: "Chinese (Simplified)", code: "zh-Hans"),
        TargetLanguage(name: "Chinese (Traditional)", code: "zh-Hant"),
        TargetLanguage(name: "Arabic", code: "ar"),
        TargetLanguage(name: "Hindi", code: "hi"),
        TargetLanguage(name: "Italian", code: "it"),
        TargetLanguage(name: "Portuguese", code: "pt-BR"),
        TargetLanguage(name: "German", code: "de"),
        TargetLanguage(name: "Russian", code: "ru"),
        TargetLanguage(name: "Vietnamese", code: "vi"),
        TargetLanguage(name: "Thai", code: "th"),
        TargetLanguage(name: "Turkish", code: "tr"),
        TargetLanguage(name: "Indonesian", code: "id"),
        TargetLanguage(name: "Polish", code: "pl"),
        TargetLanguage(name: "Dutch", code: "nl"),
        TargetLanguage(name: "Ukrainian", code: "uk")
    ]

    static func find(_ code: String) -> TargetLanguage {
        all.first { $0.code == code } ?? all[0]
    }

    static func displayName(_ language: Locale.Language) -> String {
        if let match = all.first(where: { sameLanguage($0.language, language) }) { return match.name }
        return Locale(identifier: "en").localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }

    static func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode && a.script == b.script
    }
}

enum Prefs {
    static var lastTarget: String {
        get { UserDefaults.standard.string(forKey: "lastTarget") ?? "es" }
        set { UserDefaults.standard.set(newValue, forKey: "lastTarget") }
    }
}

// MARK: - Favorites, shared between the app and the keyboard through an App Group
enum SharedStore {
    static let baseGroup = "group.com.nathanielortiz.translatekeys"
    static let defaultFavorites = ["es", "en", "fr", "ja", "ko", "zh-Hans"]

    /// Installers like AltStore and Sideloadly rename App Groups (often adding a team ID),
    /// so try the likely names and use the first one this app is actually allowed to open.
    static let groupID: String? = {
        var candidates: [String] = []
        if let altGroups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            candidates += altGroups
        }
        candidates.append(baseGroup)
        let known: Set<String> = ["com", "nathanielortiz", "translatekeys", "keyboard"]
        let extras = (Bundle.main.bundleIdentifier ?? "").split(separator: ".").map(String.init)
            .filter { !known.contains($0) }
        for extra in extras { candidates.append(baseGroup + "." + extra) }

        return candidates.first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()

    static var isShared: Bool { groupID != nil }
    private static var defaults: UserDefaults? { groupID.flatMap { UserDefaults(suiteName: $0) } }

    /// Language codes to show on the keyboard, in the order of Languages.all.
    static var favorites: [String] {
        get {
            let saved = defaults?.stringArray(forKey: "favorites") ?? defaultFavorites
            let valid = Languages.all.map(\.code).filter { saved.contains($0) }
            return valid.isEmpty ? defaultFavorites : valid
        }
        set { defaults?.set(newValue, forKey: "favorites") }
    }

    static var favoriteLanguages: [TargetLanguage] {
        // If the shared space isn't available, show every language rather than a stale list.
        guard isShared else { return Languages.all }
        let codes = favorites
        return Languages.all.filter { codes.contains($0.code) }
    }
}

// MARK: - Free on-device translation (Apple Translation framework)
enum FreeTranslator {
    /// Guess the language of the typed text.
    static func detectLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let detected = recognizer.dominantLanguage, detected != .undetermined else { return nil }
        return Locale.Language(identifier: detected.rawValue)
    }

    static func translate(_ text: String, to target: TargetLanguage) async throws -> String {
        guard let source = detectLanguage(of: text) else {
            throw fail("Couldn't tell what language this is. Type a few more words and try again.")
        }
        if Languages.sameLanguage(source, target.language) {
            throw fail("This already looks like \(target.name).")
        }

        let sourceName = Languages.displayName(source)
        let status = await LanguageAvailability().status(from: source, to: target.language)
        switch status {
        case .installed:
            break
        case .supported:
            throw fail("Download \(sourceName) and \(target.name) first: open the TranslateKeys app and tap Download.")
        case .unsupported:
            throw fail("Apple can't translate \(sourceName) to \(target.name) yet.")
        @unknown default:
            break
        }

        let session = TranslationSession(installedSource: source, target: target.language)
        let response = try await session.translate(text)
        let output = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw fail("No translation came back. Try again.") }
        return output
    }

    private static func fail(_ message: String) -> NSError {
        NSError(domain: "TranslateKeys", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
