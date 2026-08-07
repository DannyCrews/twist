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
    ///
    /// `held` is the rack positions of letters already staged in the word being typed, in the
    /// order they were typed. Those letters are not shuffled and not given up: twisting to
    /// rearrange what is left should never cost you the letters you had already committed to.
    /// They move to the end of the rack so the letters still available pack to the left and the
    /// gaps trail behind them, which reads far better than holes scattered through the row.
    ///
    /// Returns the held letters' new positions, in the same order they were passed, so the
    /// caller's staged-index list stays pointing at the same letters.
    @discardableResult
    public mutating func twist(
        holding held: [Int] = [],
        using generator: inout some RandomNumberGenerator
    ) -> [Int] {
        let heldSet = Set(held.filter(tiles.indices.contains))
        let heldLetters = held.filter(tiles.indices.contains).map { tiles[$0] }
        var free = tiles.enumerated().filter { !heldSet.contains($0.offset) }.map(\.element)

        if free.count > 1 {
            let previous = free
            // A twist that changes nothing reads as a broken button.
            for _ in 0..<8 {
                free.shuffle(using: &generator)
                if free != previous { break }
            }
        }

        tiles = free + heldLetters
        return Array(free.count..<tiles.count)
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

    /// What the board shows, grouped by length, longest group first.
    ///
    /// Every common word — the round's targets — plus any *rare* word you have actually found.
    /// Rare words you have not found stay hidden, so the target count is still the thing to
    /// chase and the board does not leak answers.
    ///
    /// Including found rare words is not decoration. The board used to show common words only,
    /// so playing a rare word scored, said so in the feedback line, and changed nothing you
    /// were looking at. On a real rack that is not an edge case: `acinst` spells 27 words with
    /// a slot and 31 without, so more than half of everything accepted vanished on entry. It
    /// reads exactly like the word was refused.
    ///
    /// Within a group the words you have found come first, in the order you found them, then
    /// the rest alphabetically. That ordering is measured: every slot in a group is the same
    /// width and every unfound one renders as identical dots, so moving unfound slots is
    /// invisible and only found words can be seen to move. Across 120 real racks, leading with
    /// found words cut the distance the eye travels from one found word to the next by 29%
    /// (216pt to 153pt), and keeping discovery order rather than re-sorting holds visible
    /// displacement at zero — re-sorting alphabetically moved earlier finds 113pt each time.
    public var boardWordsByLength: [(length: Int, words: [LexiconEntry])] {
        let discoveryRank = Dictionary(
            uniqueKeysWithValues: foundWords.enumerated().map { ($0.element, $0.offset) })
        let visible = solutions.filter { $0.isCommon || found.contains($0.word) }

        return Dictionary(grouping: visible) { $0.word.count }
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
