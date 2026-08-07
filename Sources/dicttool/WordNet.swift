import Foundation

/// Princeton WordNet, used at build time to decide which words are real English.
///
/// Build-time only — none of this reaches the app bundle. The game's definitions come from the
/// reader's own macOS dictionary at runtime; WordNet is here purely as a membership oracle, and
/// a deterministic one. That matters more than the quality of its glosses: the word list defines
/// what the game accepts and the test suite asserts against it, so it has to be reproducible
/// from shipped inputs rather than from whatever dictionary assets a given Mac happens to have.
///
/// Licence permits redistribution and commercial use without fee; see
/// https://wordnet.princeton.edu/license-and-commercial-use
struct WordNet {
    /// Lemmas exactly as WordNet stores them. Case is meaningful: WordNet capitalises proper
    /// nouns, so a lowercase lemma is evidence that a word is an ordinary common word. That is
    /// what keeps `mae`, `nam` and `mel` off the board once SUBTLEX is case-folded.
    private let lemmas: Set<String>

    /// Irregular forms WordNet cannot derive by rule — `geese` to `goose`, `oxen` to `ox`.
    private let exceptions: [String: String]

    /// Morphy's suffix rules, in WordNet's own order. Applied only when the surface form is not
    /// already a lemma, so `dogs` reaches `dog` without `bus` becoming `bu`.
    private static let rules: [(suffix: String, replacement: String)] = [
        ("ses", "s"), ("xes", "x"), ("zes", "z"), ("ches", "ch"), ("shes", "sh"),
        ("men", "man"), ("ies", "y"), ("es", "e"), ("es", ""), ("s", ""),
        ("ed", "e"), ("ed", ""), ("ing", "e"), ("ing", ""),
        ("er", ""), ("est", ""), ("er", "e"), ("est", "e"),
    ]

    /// Resolves a surface form to its lowercase WordNet lemma, or nil if WordNet has no such
    /// word. Proper nouns resolve to nil because their lemma is capitalised.
    func lemma(for word: String) -> String? {
        if lemmas.contains(word) { return word }
        if let exception = exceptions[word], lemmas.contains(exception) { return exception }
        for rule in Self.rules where word.hasSuffix(rule.suffix) {
            let stem = String(word.dropLast(rule.suffix.count)) + rule.replacement
            if stem.count >= 2, lemmas.contains(stem) { return stem }
        }
        return nil
    }

    func knows(_ word: String) -> Bool { lemma(for: word) != nil }

    var lemmaCount: Int { lemmas.count }

    // MARK: - Loading

    /// Fetches the WordNet database, unpacks it, and reads the index and exception files.
    ///
    /// Only the index and `.exc` files are needed — the `data.*` files hold the glosses, which
    /// this project does not use and does not ship.
    static func load() async throws -> WordNet {
        let root = try await unpack()

        var lemmas = Set<String>()
        var exceptions: [String: String] = [:]

        for part in ["noun", "verb", "adj", "adv"] {
            let index = root.appendingPathComponent("index.\(part)")
            guard let text = try? String(contentsOf: index, encoding: .isoLatin1) else {
                throw Failure("WordNet: missing \(index.lastPathComponent)")
            }
            for line in text.split(separator: "\n") where !line.hasPrefix("  ") {
                if let lemma = line.split(separator: " ").first {
                    // Multi-word entries are joined with underscores and can never be a rack.
                    if !lemma.contains("_") { lemmas.insert(String(lemma)) }
                }
            }

            let exceptionFile = root.appendingPathComponent("\(part).exc")
            if let text = try? String(contentsOf: exceptionFile, encoding: .isoLatin1) {
                for line in text.split(separator: "\n") {
                    let fields = line.split(separator: " ")
                    if fields.count >= 2 {
                        exceptions[String(fields[0])] = String(fields[1])
                    }
                }
            }
        }

        // 83,253 single-word lemmas in WordNet 3.1. The index files also carry multi-word
        // entries joined by underscores, which are excluded above and account for the rest of
        // the 147,478 total — a guard set against that larger figure would always trip.
        guard lemmas.count > 70_000 else {
            throw Failure("WordNet: only \(lemmas.count) lemmas parsed — the format may have changed")
        }
        return WordNet(lemmas: lemmas, exceptions: exceptions)
    }

    private static let archive = "wn3.1.dict.tar.gz"
    private static let source = URL(string: "https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz")!

    /// Downloads and extracts into `Data/wordnet/`, reusing whatever is already there.
    private static func unpack() async throws -> URL {
        let directory = URL(fileURLWithPath: "Data/wordnet", isDirectory: true)
        let root = directory.appendingPathComponent("dict")
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("index.noun").path) {
            return root
        }

        let tarball = URL(fileURLWithPath: "Data").appendingPathComponent(archive)
        if !FileManager.default.fileExists(atPath: tarball.path) {
            FileHandle.standardError.write(Data("fetching \(archive) from \(source.absoluteString)\n".utf8))
            let (data, response) = try await URLSession.shared.data(from: source)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw Failure("WordNet: HTTP \(http.statusCode)")
            }
            try FileManager.default.createDirectory(
                at: tarball.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: tarball)
            FileHandle.standardError.write(Data("  cached \(data.count) bytes\n".utf8))
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["xzf", tarball.path, "-C", directory.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw Failure("WordNet: tar exited \(tar.terminationStatus)")
        }
        return root
    }
}
