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
    /// The language you usually type in, remembered so the translator can warm up early.
    static var lastSource: String {
        get { UserDefaults.standard.string(forKey: "lastSource") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "lastSource") }
    }
}

// MARK: - Settings shared between the app and the keyboard through an App Group
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

    /// Shared with the app when the App Group works; otherwise this side's own storage,
    /// so favorites picked with the keyboard's ★ button still stick.
    private static var defaults: UserDefaults? {
        groupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Language codes to show on the keyboard, in the order of Languages.all.
    static var favorites: [String] {
        get {
            let saved = defaults?.stringArray(forKey: "favorites") ?? defaultFavorites
            let valid = Languages.all.map(\.code).filter { saved.contains($0) }
            return valid.isEmpty ? defaultFavorites : valid
        }
        set { defaults?.set(newValue, forKey: "favorites") }
    }

    /// Only the favorites, never the full list.
    static var favoriteLanguages: [TargetLanguage] {
        let codes = favorites
        return Languages.all.filter { codes.contains($0.code) }
    }

    /// Shown in the app so problems with sharing can be diagnosed.
    static var diagnostics: String {
        let alt = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.joined(separator: ", ") ?? "none"
        return "App ID: \(Bundle.main.bundleIdentifier ?? "?")\nShared space: \(groupID ?? "not found")\nInstaller groups: \(alt)"
    }

    static var keySounds: Bool {
        get { defaults?.object(forKey: "keySounds") as? Bool ?? true }
        set { defaults?.set(newValue, forKey: "keySounds") }
    }

    static var haptics: Bool {
        get { defaults?.object(forKey: "haptics") as? Bool ?? true }
        set { defaults?.set(newValue, forKey: "haptics") }
    }
}

// MARK: - Free on-device translation (Apple Translation framework), kept warm for speed
@MainActor
final class TranslatorEngine {
    static let shared = TranslatorEngine()

    private var sessions: [String: TranslationSession] = [:]
    private var installedPairs: Set<String> = []
    private var warmUp: Task<Void, Never>?
    private let availability = LanguageAvailability()

    private func key(_ s: Locale.Language, _ t: Locale.Language) -> String {
        s.minimalIdentifier + ">" + t.minimalIdentifier
    }

    /// One loaded translator per language pair. Only a couple are kept to stay within keyboard memory.
    private func session(from source: Locale.Language, to target: Locale.Language) -> TranslationSession {
        let k = key(source, target)
        if let existing = sessions[k] { return existing }
        if sessions.count >= 2 { sessions.removeAll() }
        let made: TranslationSession
        if #available(iOS 26.4, *) {
            // The faster translation model; noticeably quicker on newer iPhones.
            made = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        } else {
            made = TranslationSession(installedSource: source, target: target)
        }
        sessions[k] = made
        return made
    }

    private func isInstalled(_ source: Locale.Language, _ target: Locale.Language) async -> LanguageAvailability.Status {
        let k = key(source, target)
        if installedPairs.contains(k) { return .installed }
        let status = await availability.status(from: source, to: target)
        if status == .installed { installedPairs.insert(k) }
        return status
    }

    /// Load the translator in the background before you tap Translate.
    func prewarm(to target: TargetLanguage) {
        let source = Locale.Language(identifier: Prefs.lastSource)
        guard !Languages.sameLanguage(source, target.language) else { return }
        warmUp?.cancel()
        warmUp = Task {
            guard await isInstalled(source, target.language) == .installed, !Task.isCancelled else { return }
            let s = session(from: source, to: target.language)
            _ = try? await s.translate("Hello")
        }
    }

    func translate(_ text: String, to target: TargetLanguage) async throws -> String {
        guard let source = Self.detectLanguage(of: text) else {
            throw Self.fail("Couldn't tell what language this is. Type a few more words and try again.")
        }
        if Languages.sameLanguage(source, target.language) {
            throw Self.fail("This already looks like \(target.name).")
        }
        Prefs.lastSource = source.minimalIdentifier

        let sourceName = Languages.displayName(source)
        switch await isInstalled(source, target.language) {
        case .installed:
            break
        case .supported:
            throw Self.fail("Download \(sourceName) and \(target.name) first: open the TranslateKeys app and tap Download.")
        case .unsupported:
            throw Self.fail("Apple can't translate \(sourceName) to \(target.name) yet.")
        @unknown default:
            break
        }

        await warmUp?.value          // don't run two translations on one session at once
        let response = try await session(from: source, to: target.language).translate(text)
        let output = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw Self.fail("No translation came back. Try again.") }
        return output
    }

    /// Guess the language of the typed text, limited to languages the translator supports.
    static func detectLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Languages.all.map {
            NLLanguage(rawValue: $0.code.hasPrefix("pt") ? "pt" : $0.code)
        }
        // Lean slightly toward the language you usually type in (helps with short messages).
        recognizer.languageHints = [NLLanguage(rawValue: Prefs.lastSource): 0.4]
        recognizer.processString(text)
        guard let detected = recognizer.dominantLanguage, detected != .undetermined else { return nil }
        return Locale.Language(identifier: detected.rawValue)
    }

    private static func fail(_ message: String) -> NSError {
        NSError(domain: "TranslateKeys", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Kept so the app's "Try it here" box uses the same fast engine.
enum FreeTranslator {
    static func translate(_ text: String, to target: TargetLanguage) async throws -> String {
        try await TranslatorEngine.shared.translate(text, to: target)
    }
}
