import UIKit

/// Autocorrect and word suggestions using Apple's on-device spell checker (free, offline).
@MainActor
final class Speller {
    private let checker = UITextChecker()
    private var lexicon: Set<String> = []          // contact names, your text replacements
    private(set) var language = "en_US"

    /// Words from your contacts and text replacements, so they never get "corrected".
    func setLexicon(_ entries: [UILexiconEntry]) {
        lexicon = Set(entries.flatMap { [$0.userInput.lowercased(), $0.documentText.lowercased()] })
    }

    /// Spell-check in the language you usually type in.
    func setLanguage(fromCode code: String) {
        let base = Locale.Language(identifier: code).languageCode?.identifier ?? "en"
        let available = UITextChecker.availableLanguages
        language = available.first { $0.hasPrefix(base) }
            ?? available.first { $0.hasPrefix("en") }
            ?? "en_US"
    }

    func learn(_ word: String) {
        if !UITextChecker.hasLearnedWord(word) { UITextChecker.learnWord(word) }
    }

    private func range(_ word: String) -> NSRange { NSRange(location: 0, length: (word as NSString).length) }

    private func isKnown(_ word: String) -> Bool {
        if lexicon.contains(word.lowercased()) || UITextChecker.hasLearnedWord(word) { return true }
        let miss = checker.rangeOfMisspelledWord(in: word, range: range(word), startingAt: 0,
                                                 wrap: false, language: language)
        return miss.location == NSNotFound
    }

    /// The fix to apply when you finish a word (space, return or punctuation), if any.
    func correction(for word: String) -> String? {
        if word == "i" && language.hasPrefix("en") { return "I" }
        guard word.count >= 2,
              word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }),
              !isKnown(word),
              let guess = checker.guesses(forWordRange: range(word), in: word, language: language)?.first
        else { return nil }
        let fixed = matchCase(guess, like: word)
        return fixed == word ? nil : fixed
    }

    /// Up to two other words to offer in the suggestion bar.
    func alternatives(for word: String, excluding correction: String?) -> [String] {
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
