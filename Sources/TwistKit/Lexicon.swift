import Foundation

/// One playable word.
public struct LexiconEntry: Hashable, Sendable {
    public let word: String

    /// Whether the word is common enough that the game expects you to find it.
    ///
    /// Uncommon words still score — knowing `aalii` should be rewarded, not punished — but they
    /// are excluded from the round's target count, so "found them all" stays reachable.
    public let isCommon: Bool

    public init(word: String, isCommon: Bool) {
        self.word = word
        self.isCommon = isCommon
    }
}

/// A rack the game can deal, together with what the offline pipeline measured about it.
public struct PuzzleSpec: Hashable, Sendable {
    public let rack: Signature
    public let difficulty: Difficulty

    /// How many common words the rack spells. Drives both the difficulty bucket and the
    /// round's completion target.
    public let commonWordCount: Int

    public var rackSize: Int { rack.count }

    public init(rack: Signature, difficulty: Difficulty, commonWordCount: Int) {
        self.rack = rack
        self.difficulty = difficulty
        self.commonWordCount = commonWordCount
    }
}

public enum Difficulty: UInt8, CaseIterable, Sendable, Comparable {
    case gentle, steady, tricky, brutal

    public static func < (lhs: Difficulty, rhs: Difficulty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The word list and puzzle pool the game plays against.
public struct Lexicon: Sendable {
    /// Every accepted word, grouped by the bag of letters that spells it.
    private let entriesBySignature: [Signature: [LexiconEntry]]

    public let puzzles: [PuzzleSpec]

    /// Entries whose words contain anything but ASCII letters are dropped — they have no
    /// signature, so no rack could ever spell them.
    public init(entries: [LexiconEntry], puzzles: [PuzzleSpec]) {
        var grouped: [Signature: [LexiconEntry]] = [:]
        for entry in entries {
            guard let signature = Signature(entry.word) else { continue }
            grouped[signature, default: []].append(entry)
        }
        self.entriesBySignature = grouped
        self.puzzles = puzzles
    }

    public var wordCount: Int { entriesBySignature.values.reduce(0) { $0 + $1.count } }

    /// Every word spellable from `rack` without reusing a tile.
    public func words(spellableFrom rack: Signature, minimumLength: Int = 3) -> [LexiconEntry] {
        rack.subsignatures(minimumLength: minimumLength)
            .flatMap { entriesBySignature[$0] ?? [] }
    }

    /// The entry for an exact word, or nil if the word is not accepted.
    public func entry(for word: some StringProtocol) -> LexiconEntry? {
        guard let signature = Signature(word) else { return nil }
        let lowercased = word.lowercased()
        return entriesBySignature[signature]?.first { $0.word == lowercased }
    }

    public func puzzles(rackSize: Int) -> [PuzzleSpec] {
        puzzles.filter { $0.rackSize == rackSize }
    }
}
