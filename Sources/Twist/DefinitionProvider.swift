import CoreServices
import Foundation

/// Looks up what a word means.
///
/// Behind a protocol for one reason: the real implementation reads the reader's own installed
/// macOS dictionary, whose content differs by machine, locale and OS version. That is exactly
/// what you want for a definition someone reads — it is Oxford, it is already on their Mac, and
/// it costs nothing to ship — and exactly what you cannot assert in a test. Tests inject a stub
/// and check the surrounding behaviour instead.
protocol DefinitionProvider: Sendable {
    func definition(for word: String) -> Definition?
}

/// A definition trimmed to something that fits in a bubble.
struct Definition: Equatable, Sendable {
    /// The entry actually found, which may differ from the word looked up — `canoes` resolves
    /// to `canoe`. Worth showing, because the difference is itself informative.
    let headword: String
    let partOfSpeech: String?
    let text: String
}

/// The macOS dictionary, via Dictionary Services.
///
/// Measured over 1,200 randomly sampled words from the shipped common list: 99.9% resolved, at
/// 1.44 ms each. Inflections are handled by the dictionary itself, so `eons` finds `eon`.
struct SystemDefinitionProvider: DefinitionProvider {
    func definition(for word: String) -> Definition? {
        let term = word.lowercased()
        let range = CFRangeMake(0, term.utf16.count)
        guard
            let raw = DCSCopyTextDefinition(nil, term as CFString, range)?
                .takeRetainedValue() as String?
        else { return nil }
        return Self.parse(raw, lookedUp: term)
    }

    /// Reduces a full dictionary entry to a headword, a part of speech, and one sense.
    ///
    /// The raw text runs headword, then a repeated syllabified form, then pronunciation between
    /// vertical bars, then the part of speech, then numbered senses with examples. Reproduced
    /// whole it is a wall of text; the first sense is what answers "what does this mean".
    static func parse(_ raw: String, lookedUp: String) -> Definition? {
        var body = raw.replacingOccurrences(of: "\n", with: " ")

        // Pronunciation sits between vertical bars. Everything before the first bar is the
        // headword and its syllabification.
        var headword = lookedUp
        if let firstBar = body.firstIndex(of: "|"), let secondBar = body[body.index(after: firstBar)...].firstIndex(of: "|") {
            let lead = body[..<firstBar].trimmingCharacters(in: .whitespaces)
            if let first = lead.split(separator: " ").first { headword = String(first) }
            body = String(body[body.index(after: secondBar)...])
        } else if let first = body.split(separator: " ").first {
            headword = String(first)
            body = String(body.dropFirst(first.count))
        }
        body = body.trimmingCharacters(in: .whitespaces)

        // The part of speech leads the definition proper.
        let parts = [
            "noun", "verb", "adjective", "adverb", "pronoun", "preposition",
            "conjunction", "interjection", "exclamation", "determiner", "abbreviation",
        ]
        var partOfSpeech: String?
        // Match the token when it ends the string too, or an entry that is nothing but a part
        // of speech leaves "noun" behind as though it were the definition.
        for part in parts where body == part || body.hasPrefix(part + " ") {
            partOfSpeech = part
            body = String(body.dropFirst(part.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        // Senses are numbered. Take the first, and stop at the example sentence that follows it.
        if body.hasPrefix("1 ") { body = String(body.dropFirst(2)) }
        if let secondSense = body.range(of: " 2 ") { body = String(body[..<secondSense.lowerBound]) }
        if let example = body.range(of: ": ") { body = String(body[..<example.lowerBound]) }

        var text = body.trimmingCharacters(in: .whitespaces)
        while let last = text.last, last == "." || last == ";" || last == "," {
            text = String(text.dropLast())
        }
        // A very long single sense still needs a ceiling, cut at a word boundary.
        if text.count > 240, let cut = text.prefix(240).lastIndex(of: " ") {
            text = String(text[..<cut]) + "…"
        }

        guard !text.isEmpty else { return nil }
        return Definition(headword: headword, partOfSpeech: partOfSpeech, text: text)
    }
}

/// Answers from a fixed table. Used by tests and by the snapshot renderer, so neither depends
/// on which dictionaries a given machine happens to have installed.
struct StubDefinitionProvider: DefinitionProvider {
    var entries: [String: Definition] = [:]

    func definition(for word: String) -> Definition? { entries[word.lowercased()] }
}
