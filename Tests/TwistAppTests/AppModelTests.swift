import Foundation
import Testing
import TwistKit

@testable import Twist

private let lexicon = Lexicon(
    entries: [
        LexiconEntry(word: "stream", isCommon: true),
        LexiconEntry(word: "steam", isCommon: true),
        LexiconEntry(word: "sea", isCommon: true),
        LexiconEntry(word: "praised", isCommon: true),
        LexiconEntry(word: "spider", isCommon: true),
        LexiconEntry(word: "ride", isCommon: true),
    ],
    puzzles: [
        PuzzleSpec(rack: Signature("stream")!, difficulty: .steady, commonWordCount: 3),
        PuzzleSpec(rack: Signature("praised")!, difficulty: .gentle, commonWordCount: 3),
    ]
)

@MainActor
private func makeApp() -> (app: AppModel, url: URL) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("twist-tests-\(UUID().uuidString)")
        .appendingPathComponent("history.json")
    return (AppModel(lexicon: lexicon, store: HistoryStore(fileURL: url)), url)
}

@MainActor
@Test func theAppOpensOnTheMenuRatherThanARunningGame() {
    let (app, _) = makeApp()
    #expect(app.game == nil)

    app.startGame()
    #expect(app.game != nil)

    app.returnToMenu()
    #expect(app.game == nil)
}

@MainActor
@Test func theGameIsBuiltWithTheModeChosenOnTheMenu() {
    let (app, _) = makeApp()

    app.settings.clock = .untimed
    app.settings.rackSizes = [7]
    app.startGame()

    // Untimed play and single-size racks were unreachable before the menu existed; this is the
    // wiring that makes the choice reach the round.
    #expect(app.game?.secondsRemaining == nil)
    #expect(app.game?.round.puzzle.rackSize == 7)

    app.returnToMenu()
    app.settings.clock = .timed(seconds: 120)
    app.settings.rackSizes = [6]
    app.startGame()
    #expect(app.game?.secondsRemaining == 120)
    #expect(app.game?.round.puzzle.rackSize == 6)
}

@MainActor
@Test func returningToTheMenuPicksUpTheGameJustFinished() throws {
    let (app, url) = makeApp()
    let store = HistoryStore(fileURL: url)
    #expect(app.history.isEmpty)

    // A game recorded by any route — the running session, or a previous launch.
    try store.append(
        GameRecord(
            finishedAt: Date(), score: 4200, roundsCleared: 2, roundsCompleted: 1,
            wordsFound: 18, bingosFound: 2, rackSizes: [6], wasTimed: true))

    app.returnToMenu()
    #expect(app.history.count == 1)
    #expect(app.statistics.bestScore == 4200)
}

@MainActor
@Test func resettingFromTheMenuEmptiesTheHistory() throws {
    let (app, url) = makeApp()
    try HistoryStore(fileURL: url).append(
        GameRecord(
            finishedAt: Date(), score: 900, roundsCleared: 1, roundsCompleted: 0,
            wordsFound: 4, bingosFound: 1, rackSizes: [6], wasTimed: true))
    app.returnToMenu()
    #expect(app.history.count == 1)

    app.resetHistory()
    #expect(app.history.isEmpty)
    #expect(app.statistics.gamesPlayed == 0)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@MainActor
@Test func aGameCanBeStartedFinishedAndStartedAgain() {
    let (app, _) = makeApp()
    app.startGame()
    let first = app.game
    #expect(first != nil)
    first?.endRound()
    first?.advance()

    app.returnToMenu()
    app.startGame()
    #expect(app.game != nil)
    #expect(app.game !== first)
}
