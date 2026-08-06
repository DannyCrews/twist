import Testing
@testable import TwistKit

/// A lexicon with several racks, so dealing and advancing have somewhere to go.
private func makeLexicon() -> Lexicon {
    let racks: [(String, [String], Difficulty)] = [
        ("stream", ["steam", "tears", "rest", "sea", "art"], .gentle),
        ("planet", ["plane", "plant", "leant", "plan", "lane", "net"], .gentle),
        ("garden", ["danger", "grand", "range", "dare", "gear", "red"], .steady),
        ("silent", ["listen", "tinsel", "inlet", "line", "lens", "tin"], .steady),
        ("cabaret", ["cabare", "crate", "trace", "beat", "care", "bat"], .tricky),
        ("sneaker", ["sneak", "snare", "reeks", "near", "ease", "ran"], .tricky),
        ("armada", ["drama", "arm", "ram", "mad", "dam"], .brutal),
        ("scheme", ["seem", "mesh", "she", "see", "hem"], .brutal),
    ]

    var entries: [LexiconEntry] = []
    var puzzles: [PuzzleSpec] = []
    for (rack, subwords, difficulty) in racks {
        entries.append(LexiconEntry(word: rack, isCommon: true))
        entries.append(contentsOf: subwords.map { LexiconEntry(word: $0, isCommon: true) })
        puzzles.append(
            PuzzleSpec(
                rack: Signature(rack)!,
                difficulty: difficulty,
                // The rack itself plus its subwords, minus any that are anagrams of the rack
                // (those are counted once by signature).
                commonWordCount: 1 + subwords.count))
    }
    return Lexicon(entries: entries, puzzles: puzzles)
}

private func makeSession(
    _ settings: GameSettings = GameSettings(rackSizes: [6, 7]),
    seed: UInt64 = 42
) -> GameSession {
    GameSession(lexicon: makeLexicon(), settings: settings, generator: TwistRandom(seed: seed))!
}

@Test func sessionStartsOnRoundOnePlaying() {
    let session = makeSession()
    #expect(session.state == .playing)
    #expect(session.roundNumber == 1)
    #expect(session.score == 0)
    #expect(session.completedRounds.isEmpty)
}

@Test func sessionRefusesToStartWithoutAPuzzle() {
    let empty = Lexicon(entries: [], puzzles: [])
    #expect(GameSession(lexicon: empty) == nil)
}

@Test func submittingScoresIntoTheRunningTotal() {
    var session = makeSession()
    let word = session.round.puzzle.rack.letters  // sorted letters are not a word
    let rejection = session.submit(word)
    #expect(rejection == .notAWord(word: word))

    let bingo = session.round.solutions.first { $0.word.count == session.round.puzzle.rackSize }!
    session.submit(bingo.word)
    #expect(session.score == Scoring.points(for: bingo.word))
}

@Test func endingARoundBanksItAndOffersReview() {
    var session = makeSession()
    let bingo = session.round.solutions.first { $0.word.count == session.round.puzzle.rackSize }!
    session.submit(bingo.word)
    session.endRound()

    guard case .reviewing(let summary, let canContinue) = session.state else {
        Issue.record("expected review state, got \(session.state)")
        return
    }
    #expect(canContinue)
    #expect(summary.foundBingo)
    #expect(!summary.completed)  // subwords still outstanding
    #expect(summary.score == Scoring.points(for: bingo.word))
    #expect(session.bankedScore == summary.score)
    #expect(!summary.missedWords.isEmpty)
}

@Test func advancingRequiresTheBingoWord() {
    var session = makeSession()
    // Find a short word, but never the full-rack one.
    let short = session.round.solutions.first { $0.word.count < session.round.puzzle.rackSize }!
    session.submit(short.word)
    session.endRound()

    guard case .reviewing(_, let canContinue) = session.state else {
        Issue.record("expected review state")
        return
    }
    #expect(!canContinue)
    let advanced = session.advance()
    #expect(advanced == false)
    #expect(session.state == .finished)
    #expect(session.roundNumber == 1)
}

@Test func advancingDealsAFreshRack() {
    var session = makeSession()
    var seen: Set<Signature> = [session.round.puzzle.rack]

    for expectedRound in 2...5 {
        let bingo = session.round.solutions.first {
            $0.word.count == session.round.puzzle.rackSize
        }!
        session.submit(bingo.word)
        session.endRound()
        let advanced = session.advance()
        #expect(advanced)
        #expect(session.state == .playing)
        #expect(session.roundNumber == expectedRound)
        #expect(seen.insert(session.round.puzzle.rack).inserted, "round \(expectedRound) repeated a rack")
        seen.insert(session.round.puzzle.rack)
    }
    #expect(session.completedRounds.count == 4)
}

@Test func theSittingEndsWhenThePoolRunsOut() {
    // Eight racks in the lexicon, so the ninth deal has nothing left.
    var session = makeSession()
    for _ in 1...8 {
        guard session.state == .playing else { break }
        let bingo = session.round.solutions.first {
            $0.word.count == session.round.puzzle.rackSize
        }!
        session.submit(bingo.word)
        session.endRound()
        session.advance()
    }
    #expect(session.state == .finished)
}

@Test func difficultyClimbsEveryThreeRounds() {
    #expect(GameSession.difficulty(forRound: 1) == .gentle)
    #expect(GameSession.difficulty(forRound: 3) == .gentle)
    #expect(GameSession.difficulty(forRound: 4) == .steady)
    #expect(GameSession.difficulty(forRound: 7) == .tricky)
    #expect(GameSession.difficulty(forRound: 10) == .brutal)
    #expect(GameSession.difficulty(forRound: 99) == .brutal)
}

@Test func settingsPinTheRackSize() {
    var session = makeSession(GameSettings(rackSizes: [7]), seed: 7)
    for _ in 1...3 {
        #expect(session.round.puzzle.rackSize == 7)
        let bingo = session.round.solutions.first {
            $0.word.count == session.round.puzzle.rackSize
        }!
        session.submit(bingo.word)
        session.endRound()
        guard session.advance() else { break }
    }
}

@Test func untimedSettingsReportNoLimit() {
    #expect(GameSettings(clock: .untimed).secondsPerRound == nil)
    #expect(GameSettings(clock: .timed(seconds: 120)).secondsPerRound == 120)
    #expect(GameSettings().secondsPerRound == 120)  // the original's two minutes
}

@Test func emptyRackSizesFallBackToSix() {
    #expect(GameSettings(rackSizes: []).rackSizes == [6])
}

@Test func playIsIgnoredWhileReviewing() {
    var session = makeSession()
    session.endRound()
    let before = session.round.tiles
    session.twist()
    #expect(session.round.tiles == before)
    let ignored = session.submit("sea")
    #expect(ignored == .tooShort)
}
