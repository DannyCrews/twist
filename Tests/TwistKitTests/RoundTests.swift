import Testing
@testable import TwistKit

/// Reproducible randomness, so a shuffle never makes a test flaky.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64 = 0x5EED) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// `stream` spells these and nothing else, as far as this lexicon is concerned.
private let testLexicon = Lexicon(
    entries: [
        LexiconEntry(word: "stream", isCommon: true),
        LexiconEntry(word: "master", isCommon: true),
        LexiconEntry(word: "steam", isCommon: true),
        LexiconEntry(word: "tears", isCommon: true),
        LexiconEntry(word: "rest", isCommon: true),
        LexiconEntry(word: "sea", isCommon: true),
        LexiconEntry(word: "ares", isCommon: false),
        LexiconEntry(word: "tres", isCommon: false),
    ],
    puzzles: []
)

private let testPuzzle = PuzzleSpec(
    rack: Signature("stream")!, difficulty: .steady, commonWordCount: 6)

private func makeRound() -> Round {
    var generator = SeededGenerator()
    return Round(puzzle: testPuzzle, lexicon: testLexicon, using: &generator)
}

@Test func roundDealsEveryTileExactlyOnce() {
    let round = makeRound()
    #expect(round.tiles.sorted() == Array("aemrst"))
    #expect(round.solutions.count == 8)
}

@Test func openingRackDoesNotAlreadySpellABingoWord() {
    // Deal many racks; none should read as a full-rack word on the first frame.
    for seed in UInt64(1)...200 {
        var generator = SeededGenerator(seed: seed)
        let round = Round(puzzle: testPuzzle, lexicon: testLexicon, using: &generator)
        #expect(!["stream", "master"].contains(String(round.tiles)), "seed \(seed)")
    }
}

@Test func acceptingAWordScoresIt() {
    var round = makeRound()
    #expect(round.submit("steam") == .accepted(word: "steam", points: 250, isBingo: false))
    #expect(round.wordScore == 250)
    #expect(round.foundWords == ["steam"])
    #expect(round.hasFound("STEAM"))
}

@Test func submissionsAreCaseAndWhitespaceInsensitive() {
    var round = makeRound()
    #expect(round.submit("  SteaM \t") == .accepted(word: "steam", points: 250, isBingo: false))
}

@Test func aFullRackWordIsABingo() {
    var round = makeRound()
    #expect(round.submit("stream") == .accepted(word: "stream", points: 360, isBingo: true))
    #expect(round.hasFoundBingo)
}

@Test func rejectionsAreDistinguished() {
    var round = makeRound()
    #expect(round.submit("at") == .tooShort)
    #expect(round.submit("zebra") == .notSpellableFromRack)   // no z, no b
    #expect(round.submit("streams") == .notSpellableFromRack)  // only one s
    #expect(round.submit("mates") == .notAWord(word: "mates")) // spellable, not in lexicon
    #expect(round.wordScore == 0)
}

@Test func aWordCountsOnlyOnce() {
    var round = makeRound()
    #expect(round.submit("sea") == .accepted(word: "sea", points: 90, isBingo: false))
    #expect(round.submit("sea") == .alreadyFound(word: "sea"))
    #expect(round.wordScore == 90)
    #expect(round.foundWords == ["sea"])
}

@Test func rareWordsScoreButAreNotRequired() {
    var round = makeRound()
    #expect(round.submit("ares") == .accepted(word: "ares", points: 160, isBingo: false))
    #expect(round.wordScore == 160)
    #expect(round.commonWordsFound == 0)
    #expect(!round.isComplete)
}

@Test func completionNeedsEveryCommonWordAndDoublesTheScore() {
    var round = makeRound()
    for word in ["stream", "master", "steam", "tears", "rest"] {
        round.submit(word)
    }
    #expect(!round.isComplete)
    #expect(round.totalScore == round.wordScore)

    round.submit("sea")
    #expect(round.isComplete)
    // 360 + 360 + 250 + 250 + 160 + 90 = 1470, doubled.
    #expect(round.wordScore == 1470)
    #expect(round.totalScore == 2940)
}

@Test func missedWordsListsOnlyCommonOnesLongestFirst() {
    var round = makeRound()
    round.submit("stream")
    round.submit("sea")
    #expect(round.missedWords.map(\.word) == ["master", "steam", "tears", "rest"])
}

@Test func twistChangesTheVisibleOrderAndNothingElse() {
    var round = makeRound()
    var generator = SeededGenerator(seed: 99)
    let before = round.tiles

    round.twist(using: &generator)
    #expect(round.tiles != before)
    #expect(round.tiles.sorted() == before.sorted())
    #expect(round.solutions.count == 8)

    // Twisting mid-round must not disturb progress.
    round.submit("steam")
    round.twist(using: &generator)
    #expect(round.foundWords == ["steam"])
    #expect(round.wordScore == 250)
}

@Test func scoringCurveRewardsLength() {
    #expect(Scoring.points(forWordOfLength: 3) == 90)
    #expect(Scoring.points(forWordOfLength: 4) == 160)
    #expect(Scoring.points(forWordOfLength: 5) == 250)
    #expect(Scoring.points(forWordOfLength: 6) == 360)
    #expect(Scoring.points(forWordOfLength: 7) == 490)
    #expect(Scoring.points(forWordOfLength: 2) == 0)
}
