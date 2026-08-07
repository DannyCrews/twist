import Foundation
import TwistKit

/// The two public datasets the lexicon is built from, cached under `Data/` after first fetch.
enum Input: String, CaseIterable {
    /// ENABLE (Enhanced North American Benchmark Lexicon), Alan Beale. Public domain, and the
    /// de facto standard word list for free word games. 172,819 words.
    case enable = "enable1.txt"

    /// Word counts from SUBTLEXus, a corpus of American English movie subtitles. 74,286 words.
    /// The npm wrapper this comes from is ISC-licensed.
    case subtlex = "subtlex.json"

    /// LDNOOBW, a widely used profanity list, CC BY 4.0. Covers the obscenity half; the slurs
    /// come from the repo's own blocklist.txt.
    case profanity = "ldnoobw-en.txt"

    var url: URL {
        switch self {
        case .enable:
            URL(string: "https://raw.githubusercontent.com/dolph/dictionary/master/enable1.txt")!
        case .subtlex:
            URL(string: "https://raw.githubusercontent.com/words/subtlex-word-frequencies/master/index.json")!
        case .profanity:
            URL(string: "https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/en")!
        }
    }

    var cacheURL: URL {
        URL(fileURLWithPath: "Data", isDirectory: true).appendingPathComponent(rawValue)
    }

    /// The cached copy, downloading it first if it is not already on disk.
    func load() async throws -> Data {
        if let cached = FileManager.default.contents(atPath: cacheURL.path) {
            return cached
        }
        FileHandle.standardError.write(Data("fetching \(rawValue) from \(url.absoluteString)\n".utf8))
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure("\(rawValue): HTTP \(http.statusCode) from \(url.absoluteString)")
        }
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL)
        FileHandle.standardError.write(Data("  cached \(data.count) bytes\n".utf8))
        return data
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Every ENABLE word, lowercased.
func loadEnable() async throws -> [String] {
    let data = try await Input.enable.load()
    guard let text = String(data: data, encoding: .utf8) else {
        throw Failure("enable1.txt is not UTF-8")
    }
    return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
}

/// SUBTLEX counts, folded case-insensitively.
///
/// SUBTLEX capitalises an entry when the word appears capitalised more often than not, which is
/// its way of marking proper nouns. This used to drop those entries wholesale, which kept `mae`,
/// `mel` and `nam` off the board but took 4,251 ordinary words with them: `saint` scored 0
/// because `Saint` carries all 914 of its occurrences, and so did `china`, `abbey`, `acme`,
/// `adobe`, `aegis`, `mark` and `bill`.
///
/// Folding is safe now that WordNet decides which words may be targets. A proper noun has no
/// lowercase WordNet lemma, so `mae` and `nam` are excluded on that evidence instead of by
/// throwing away every capitalised count.
func loadFrequencies() async throws -> Frequencies {
    struct Entry: Decodable {
        let word: String
        let count: Int
    }
    let data = try await Input.subtlex.load()
    let entries = try JSONDecoder().decode([Entry].self, from: data)

    var folded: [String: Int] = [:]
    var lowercase: [String: Int] = [:]
    for entry in entries {
        let word = entry.word.lowercased()
        folded[word, default: 0] += entry.count
        if entry.word == word { lowercase[word, default: 0] += entry.count }
    }
    return Frequencies(folded: folded, lowercase: lowercase)
}

/// SUBTLEX counts kept two ways, because the difference between them is the signal.
///
/// A word stored lowercase is used lowercase — that is what `and`, `that` and `with` look like.
/// A word SUBTLEX stores only capitalised has zero lowercase count, and covers two very
/// different cases: ordinary words that usually begin a proper name (`saint`, `china`, `mark`,
/// `bill`) and actual proper nouns (`mae`, `nam`, `mel`). WordNet separates those two.
struct Frequencies {
    let folded: [String: Int]
    let lowercase: [String: Int]

    func count(_ word: String) -> Int { folded[word] ?? 0 }
    func lowercaseCount(_ word: String) -> Int { lowercase[word] ?? 0 }
}


/// Words the game must never deal, show, or score.
///
/// Two sources, because neither alone is enough. LDNOOBW is a profanity list and covered only
/// 5 of the 16 offensive terms found on real boards; `blocklist.txt` in this directory carries
/// the slurs it misses. Multi-word entries and anything outside the playable length are dropped
/// on the way in, since no rack could spell them anyway.
func loadBlocklist() async throws -> Set<String> {
    var blocked = Set<String>()

    let data = try await Input.profanity.load()
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let word = line.trimmingCharacters(in: .whitespaces).lowercased()
        if Tuning.wordLengths.contains(word.count), Signature(word) != nil {
            blocked.insert(word)
        }
    }

    let local = URL(fileURLWithPath: "Sources/dicttool/blocklist.txt")
    guard let text = try? String(contentsOf: local, encoding: .utf8) else {
        throw Failure("blocklist.txt is missing from \(local.path)")
    }
    for line in text.split(separator: "\n") {
        let word = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard !word.isEmpty, !word.hasPrefix("#") else { continue }
        blocked.insert(word)
    }
    return blocked
}
