import Foundation

/// The two public datasets the lexicon is built from, cached under `Data/` after first fetch.
enum Input: String, CaseIterable {
    /// ENABLE (Enhanced North American Benchmark Lexicon), Alan Beale. Public domain, and the
    /// de facto standard word list for free word games. 172,819 words.
    case enable = "enable1.txt"

    /// Word counts from SUBTLEXus, a corpus of American English movie subtitles. 74,286 words.
    /// The npm wrapper this comes from is ISC-licensed.
    case subtlex = "subtlex.json"

    var url: URL {
        switch self {
        case .enable:
            URL(string: "https://raw.githubusercontent.com/dolph/dictionary/master/enable1.txt")!
        case .subtlex:
            URL(string: "https://raw.githubusercontent.com/words/subtlex-word-frequencies/master/index.json")!
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

/// SUBTLEX counts for lowercase words only.
///
/// SUBTLEX capitalizes an entry when the word appears capitalized more often than not, which
/// is its way of marking proper nouns. Folding those in by lowercasing lets `Mae`, `Mel` and
/// `Nam` count as common English words — sampled racks offered exactly that — so capitalized
/// entries are dropped instead. Nothing playable is lost: the only common word that is always
/// capitalized is `I`, which is below the three-letter floor.
func loadFrequencies() async throws -> [String: Int] {
    struct Entry: Decodable {
        let word: String
        let count: Int
    }
    let data = try await Input.subtlex.load()
    let entries = try JSONDecoder().decode([Entry].self, from: data)
    return entries.reduce(into: [:]) { totals, entry in
        guard let first = entry.word.unicodeScalars.first, !CharacterSet.uppercaseLetters.contains(first)
        else { return }
        totals[entry.word, default: 0] += entry.count
    }
}
