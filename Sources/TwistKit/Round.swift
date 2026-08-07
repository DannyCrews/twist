/// One rack, played to exhaustion or to the buzzer.
///
/// Deliberately clock-free: a round knows what has been found and what it is worth, and the
/// session above it owns the timer. That keeps every rule in here testable without waiting.
public struct Round: Sendable {
    public static let minimumWordLength = 3

    public let puzzle: PuzzleSpec

    /// Every word the rack spells, common and rare alike.
    public let solutions: [LexiconEntry]

    /// The rack as currently displayed. Twisting permutes this; it never changes which words
    /// are legal.
    public private(set) var tiles: [Character]

    public private(set) var foundWords: [String] = []
    private var found: Set<String> = []

    /// Score from words alone. The completion bonus is applied by `totalScore`.
    public private(set) var wordScore: Int = 0

    public enum Submission: Equatable, Sendable {
        case accepted(word: String, points: Int, isBingo: Bool)
        case alreadyFound(word: String)
        case tooShort
        case notSpellableFromRack
        case notAWord(word: String)
    }

    public init(
        puzzle: PuzzleSpec,
        lexicon: Lexicon,
        using generator: inout some RandomNumberGenerator
    ) {
        self.puzzle = puzzle
        self.solutions = lexicon.words(
            spellableFrom: puzzle.rack, minimumLength: Self.minimumWordLength)
        self.tiles = Self.scramble(puzzle.rack, solutions: solutions, using: &generator)
    }

    // MARK: - Playing

    @discardableResult
    public mutating func submit(_ raw: some StringProtocol) -> Submission {
        let word = raw.trimmingASCIIWhitespace.lowercased()

        guard word.count >= Self.minimumWordLength else { return .tooShort }
        guard let signature = Signature(word), signature.isContained(in: puzzle.rack) else {
            return .notSpellableFromRack
        }
        guard solutions.contains(where: { $0.word == word }) else {
            return .notAWord(word: word)
        }
        guard found.insert(word).inserted else { return .alreadyFound(word: word) }

        foundWords.append(word)
        let points = Scoring.points(for: word)
        wordScore += points
        return .accepted(word: word, points: points, isBingo: word.count == puzzle.rackSize)
    }

    /// Rearranges the rack. The original's one and only aid, and still the good one.
    public mutating func twist(using generator: inout some RandomNumberGenerator) {
        guard tiles.count > 1 else { return }
        let previous = tiles
        // A twist that changes nothing reads as a broken button.
        for _ in 0..<8 {
            tiles.shuffle(using: &generator)
            if tiles != previous { return }
        }
    }

    // MARK: - Progress

    public func hasFound(_ word: some StringProtocol) -> Bool {
        found.contains(word.lowercased())
    }

    /// Whether a word using every tile has been found — the original's gate on advancing.
    public var hasFoundBingo: Bool {
        found.contains { $0.count == puzzle.rackSize }
    }

    public var commonWordsFound: Int {
        solutions.count { $0.isCommon && found.contains($0.word) }
    }

    /// True once every common word is found. Rare words are a bonus, never a requirement.
    public var isComplete: Bool {
        commonWordsFound >= puzzle.commonWordCount
    }

    public var totalScore: Int {
        wordScore + Scoring.bonus(forWordScore: wordScore, completed: isComplete)
    }

    /// The common words grouped by length, longest group first. Within a group, the words you
    /// have found come first in the order you found them, then the rest.
    ///
    /// This is what the board shows as slots. Seeing that a rack holds four five-letter words
    /// is most of the game's guidance, and the original showed exactly this.
    ///
    /// The ordering is measured rather than chosen. Every slot in a group is the same width
    /// and every unfound one renders as identical dots, so rearranging unfound slots is
    /// invisible — only found words can be seen to move. Against 120 real racks, packing found
    /// words to the front cut the distance the eye travels from one found word to the next by
    /// 29% (216pt to 153pt). Keeping them in discovery order rather than re-sorting them means
    /// a word already on the board never moves again: measured visible displacement is zero,
    /// where re-sorting the found block alphabetically moved earlier finds by 113pt each time.
    ///
    /// The cost is that found words are no longer alphabetical, which would matter if you had
    /// to scan the board to check whether you had already played something. You do not —
    /// submitting a duplicate says so.
    public var commonWordsByLength: [(length: Int, words: [LexiconEntry])] {
        let discoveryRank = Dictionary(
            uniqueKeysWithValues: foundWords.enumerated().map { ($0.element, $0.offset) })

        return Dictionary(grouping: solutions.filter(\.isCommon)) { $0.word.count }
            .sorted { $0.key > $1.key }
            .map { length, words in
                let sorted = words.sorted { left, right in
                    switch (discoveryRank[left.word], discoveryRank[right.word]) {
                    case let (l?, r?): l < r          // both found: order of discovery
                    case (_?, nil): true              // found words lead
                    case (nil, _?): false
                    case (nil, nil): left.word < right.word
                    }
                }
                return (length: length, words: sorted)
            }
    }

    /// The common words left on the table, longest first — what the post-round review shows.
    public var missedWords: [LexiconEntry] {
        solutions
            .filter { $0.isCommon && !found.contains($0.word) }
            .sorted {
                $0.word.count == $1.word.count
                    ? $0.word < $1.word
                    : $0.word.count > $1.word.count
            }
    }

    // MARK: - Dealing

    /// Shuffles the rack into a starting order that does not already spell a solution.
    ///
    /// Dealing a rack that reads `ARMADA` on the first frame gives the round away.
    private static func scramble(
        _ rack: Signature,
        solutions: [LexiconEntry],
        using generator: inout some RandomNumberGenerator
    ) -> [Character] {
        let fullRackWords = Set(solutions.lazy.filter { $0.word.count == rack.count }.map(\.word))
        var tiles = Array(rack.letters)
        for _ in 0..<16 {
            tiles.shuffle(using: &generator)
            if !fullRackWords.contains(String(tiles)) { return tiles }
        }
        return tiles
    }
}

extension StringProtocol {
    /// Trims spaces and tabs without pulling in Foundation.
    var trimmingASCIIWhitespace: String {
        let trimmed = drop { $0 == " " || $0 == "\t" }.reversed()
            .drop { $0 == " " || $0 == "\t" }.reversed()
        return String(trimmed)
    }
}
