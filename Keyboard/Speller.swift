import UIKit

/// Autocorrect and word suggestions using Apple's on-device spell checker (free, offline).
/// All checking happens on its own background queue so typing never waits on it.
final class Speller: @unchecked Sendable {
    private let queue = DispatchQueue(label: "TranslateKeys.speller", qos: .userInitiated)
    private let checker = UITextChecker()          // only touched on `queue`
    private var lexicon: Set<String> = []          // contact names, your text replacements (queue only)
    private var language = "en_US"                 // queue only

    /// Words from your contacts and text replacements, so they never get "corrected".
    func setLexicon(_ entries: [UILexiconEntry]) {
        let words = Set(entries.flatMap { [$0.userInput.lowercased(), $0.documentText.lowercased()] })
        queue.async { self.lexicon = words }
    }

    /// Spell-check in the language you usually type in.
    func setLanguage(fromCode code: String) {
        let base = Locale.Language(identifier: code).languageCode?.identifier ?? "en"
        queue.async {
            let available = UITextChecker.availableLanguages
            self.language = available.first { $0.hasPrefix(base) }
                ?? available.first { $0.hasPrefix("en") }
                ?? "en_US"
        }
    }

    func learn(_ word: String) {
        queue.async { if !UITextChecker.hasLearnedWord(word) { UITextChecker.learnWord(word) } }
    }

    /// Background: the correction and alternatives for a word, delivered on the main thread.
    func suggest(for word: String, completion: @escaping (_ correction: String?, _ others: [String]) -> Void) {
        queue.async {
            let fix = self.correction(for: word)
            let others = self.alternatives(for: word, excluding: fix)
            DispatchQueue.main.async { completion(fix, others) }
        }
    }

    /// Right now (used when you finish a word before the background check came back).
    func correctionNow(for word: String) -> String? {
        queue.sync { correction(for: word) }
    }

    // MARK: Queue-only helpers

    private func range(_ word: String) -> NSRange { NSRange(location: 0, length: (word as NSString).length) }

    private func isKnown(_ word: String) -> Bool {
        if lexicon.contains(word.lowercased()) || UITextChecker.hasLearnedWord(word) { return true }
        let miss = checker.rangeOfMisspelledWord(in: word, range: range(word), startingAt: 0,
                                                 wrap: false, language: language)
        return miss.location == NSNotFound
    }

    private func correction(for word: String) -> String? {
        if word == "i" && language.hasPrefix("en") { return "I" }
        guard word.count >= 2,
              word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }),
              !isKnown(word),
              let guess = checker.guesses(forWordRange: range(word), in: word, language: language)?.first
        else { return nil }
        let fixed = matchCase(guess, like: word)
        return fixed == word ? nil : fixed
    }

    private func alternatives(for word: String, excluding correction: String?) -> [String] {
        guard !word.isEmpty else { return [] }
        var list: [String] = []
        if correction != nil {
            list += checker.guesses(forWordRange: range(word), in: word, language: language) ?? []
        }
        list += checker.completions(forPartialWordRange: range(word), in: word, language: language) ?? []
        var seen = Set([word.lowercased(), correction?.lowercased() ?? ""])
        var result: [String] = []
        for candidate in list {
            let c = matchCase(candidate, like: word)
            if seen.insert(c.lowercased()).inserted { result.append(c) }
            if result.count == 2 { break }
        }
        return result
    }

    private func matchCase(_ s: String, like original: String) -> String {
        if original.count > 1 && original == original.uppercased() { return s.uppercased() }
        if let first = original.first, first.isUppercase { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }
}
