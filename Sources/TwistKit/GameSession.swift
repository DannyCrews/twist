/// How a sitting is configured. Text Twist 2 added the untimed mode and seven-letter racks;
/// both are options here rather than separate games.
public struct GameSettings: Equatable, Sendable {
    public enum Clock: Equatable, Sendable {
        /// The original's two minutes, or any other limit.
        case timed(seconds: Int)
        /// No pressure. Rounds end when you say so.
        case untimed
    }

    public var clock: Clock
    /// Rack sizes to draw from. Both means each round picks one at random.
    public var rackSizes: Set<Int>

    public init(clock: Clock = .timed(seconds: 120), rackSizes: Set<Int> = [6]) {
        self.clock = clock
        self.rackSizes = rackSizes.isEmpty ? [6] : rackSizes
    }

    public var secondsPerRound: Int? {
        if case .timed(let seconds) = clock { seconds } else { nil }
    }
}

/// What a finished round was worth.
public struct RoundSummary: Equatable, Sendable {
    public let rack: Signature
    public let difficulty: Difficulty
    public let foundWords: [String]
    public let missedWords: [String]
    public let wordScore: Int
    public let bonus: Int
    public let foundBingo: Bool
    public let completed: Bool

    public var score: Int { wordScore + bonus }

    init(_ round: Round) {
        rack = round.puzzle.rack
        difficulty = round.puzzle.difficulty
        foundWords = round.foundWords
        missedWords = round.missedWords.map(\.word)
        wordScore = round.wordScore
        bonus = Scoring.bonus(forWordScore: round.wordScore, completed: round.isComplete)
        foundBingo = round.hasFoundBingo
        completed = round.isComplete
    }
}

/// A sitting: a run of rounds, a running score, and a difficulty that climbs as you go.
public struct GameSession: Sendable {
    public enum State: Equatable, Sendable {
        case playing
        /// The round is over and can be reviewed. `canContinue` says whether another follows.
        case reviewing(RoundSummary, canContinue: Bool)
        case finished
    }

    public let settings: GameSettings
    public private(set) var state: State = .playing
    public private(set) var round: Round
    public private(set) var roundNumber = 1
    public private(set) var completedRounds: [RoundSummary] = []

    private let lexicon: Lexicon
    private var generator: TwistRandom
    private var dealtRacks: Set<Signature> = []

    /// Score banked from finished rounds. The round in progress is not counted until it ends.
    public var bankedScore: Int { completedRounds.reduce(0) { $0 + $1.score } }

    /// What the scoreboard shows: banked plus what the current round is worth so far.
    public var score: Int {
        bankedScore + (state == .playing ? round.totalScore : 0)
    }

    public init?(
        lexicon: Lexicon,
        settings: GameSettings = GameSettings(),
        generator: TwistRandom = TwistRandom()
    ) {
        self.lexicon = lexicon
        self.settings = settings
        self.generator = generator

        guard let puzzle = Self.deal(
            from: lexicon, settings: settings, roundNumber: 1,
            excluding: [], using: &self.generator)
        else { return nil }

        self.dealtRacks = [puzzle.rack]
        self.round = Round(puzzle: puzzle, lexicon: lexicon, using: &self.generator)
    }

    // MARK: - Playing

    @discardableResult
    public mutating func submit(_ word: some StringProtocol) -> Round.Submission {
        guard state == .playing else { return .tooShort }
        return round.submit(word)
    }

    public mutating func twist() {
        guard state == .playing else { return }
        round.twist(using: &generator)
    }

    /// Ends the round, whether the clock ran out or the player chose to move on.
    ///
    /// Advancing requires the full-rack word, exactly as in the original. Without it the
    /// sitting is over — which is why the review screen exists, and why it leads with what
    /// was missed.
    public mutating func endRound() {
        guard state == .playing else { return }
        let summary = RoundSummary(round)
        completedRounds.append(summary)
        state = .reviewing(summary, canContinue: summary.foundBingo)
    }

    /// Deals the next rack. Returns false when the sitting is over, or when the pool has no
    /// rack left that matches the settings.
    @discardableResult
    public mutating func advance() -> Bool {
        guard case .reviewing(_, let canContinue) = state, canContinue else {
            state = .finished
            return false
        }
        guard let puzzle = Self.deal(
            from: lexicon, settings: settings, roundNumber: roundNumber + 1,
            excluding: dealtRacks, using: &generator)
        else {
            state = .finished
            return false
        }

        roundNumber += 1
        dealtRacks.insert(puzzle.rack)
        round = Round(puzzle: puzzle, lexicon: lexicon, using: &generator)
        state = .playing
        return true
    }

    // MARK: - Dealing

    /// Difficulty for a given round. Three rounds at each tier, then it stays brutal.
    static func difficulty(forRound number: Int) -> Difficulty {
        let tier = (max(1, number) - 1) / 3
        return Difficulty.allCases[min(tier, Difficulty.allCases.count - 1)]
    }

    private static func deal(
        from lexicon: Lexicon,
        settings: GameSettings,
        roundNumber: Int,
        excluding dealt: Set<Signature>,
        using generator: inout TwistRandom
    ) -> PuzzleSpec? {
        let size = settings.rackSizes.sorted().randomElement(using: &generator) ?? 6
        let target = difficulty(forRound: roundNumber)

        // Widen the search rather than repeat a rack: exact tier at the chosen size, then any
        // tier at that size, then any size the settings allow. Never outside those sizes — a
        // player who asked for seven-letter racks would rather the sitting end than be handed
        // a six.
        let pools: [[PuzzleSpec]] = [
            lexicon.puzzles.filter { $0.rackSize == size && $0.difficulty == target },
            lexicon.puzzles.filter { $0.rackSize == size },
            lexicon.puzzles.filter { settings.rackSizes.contains($0.rackSize) },
        ]
        for pool in pools {
            let fresh = pool.filter { !dealt.contains($0.rack) }
            if let puzzle = fresh.randomElement(using: &generator) { return puzzle }
        }
        return nil
    }
}
