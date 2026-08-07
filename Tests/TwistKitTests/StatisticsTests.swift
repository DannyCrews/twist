import Foundation
import Testing
@testable import TwistKit

private func record(
    daysAgo: Int, score: Int, words: Int = 10, bingos: Int = 1, sizes: [Int] = [6]
) -> GameRecord {
    let day = Calendar.current.date(
        byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date()))!
    return GameRecord(
        finishedAt: day.addingTimeInterval(3600),
        score: score,
        roundsCleared: bingos,
        roundsCompleted: 0,
        wordsFound: words,
        bingosFound: bingos,
        rackSizes: sizes,
        wasTimed: true)
}

@Test func statisticsOfAnEmptyHistoryAreAllZero() {
    let stats = Statistics(records: [])
    #expect(stats.gamesPlayed == 0)
    #expect(stats.bestScore == 0)
    #expect(stats.averageScore == 0)  // must not divide by zero
    #expect(stats.currentStreak == 0)
    #expect(stats.longestStreak == 0)
}

@Test func statisticsAggregateAcrossGames() {
    let stats = Statistics(records: [
        record(daysAgo: 0, score: 4000, words: 30, bingos: 3),
        record(daysAgo: 1, score: 9000, words: 50, bingos: 5),
        record(daysAgo: 2, score: 2000, words: 12, bingos: 1),
    ])
    #expect(stats.gamesPlayed == 3)
    #expect(stats.bestScore == 9000)
    #expect(stats.totalScore == 15000)
    #expect(stats.averageScore == 5000)
    #expect(stats.wordsFound == 92)
    #expect(stats.bingosFound == 9)
}

@Test func aRunOfConsecutiveDaysIsAStreak() {
    let stats = Statistics(records: [
        record(daysAgo: 0, score: 100),
        record(daysAgo: 1, score: 100),
        record(daysAgo: 2, score: 100),
    ])
    #expect(stats.currentStreak == 3)
    #expect(stats.longestStreak == 3)
}

@Test func severalGamesInOneDayAreStillOneDayOfStreak() {
    let stats = Statistics(records: [
        record(daysAgo: 0, score: 100),
        record(daysAgo: 0, score: 200),
        record(daysAgo: 1, score: 300),
    ])
    #expect(stats.currentStreak == 2)
    #expect(stats.gamesPlayed == 3)
}

@Test func yesterdayStillCountsAsCurrentButAGapDoesNot() {
    let unbroken = Statistics(records: [
        record(daysAgo: 1, score: 100), record(daysAgo: 2, score: 100),
    ])
    #expect(unbroken.currentStreak == 2)

    let stale = Statistics(records: [record(daysAgo: 5, score: 100), record(daysAgo: 6, score: 100)])
    #expect(stale.currentStreak == 0)
    #expect(stale.longestStreak == 2)  // the run happened, it is just over
}

@Test func longestStreakSurvivesALaterGap() {
    let stats = Statistics(records: [
        record(daysAgo: 10, score: 100),
        record(daysAgo: 9, score: 100),
        record(daysAgo: 8, score: 100),
        record(daysAgo: 7, score: 100),
        record(daysAgo: 0, score: 100),
    ])
    #expect(stats.longestStreak == 4)
    #expect(stats.currentStreak == 1)
}

@Test func bestScoresSplitByRackSize() {
    let best = Statistics.bestScores(byRackSize: [
        record(daysAgo: 0, score: 5000, sizes: [6, 6]),
        record(daysAgo: 1, score: 8000, sizes: [7, 7]),
        record(daysAgo: 2, score: 9000, sizes: [6, 7]),
    ])
    #expect(best[6] == 9000)
    #expect(best[7] == 9000)
    #expect(best[5] == nil)
}

@Test func historyRoundTripsThroughDisk() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("twist-tests-\(UUID().uuidString)")
        .appendingPathComponent("history.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = HistoryStore(fileURL: url)
    #expect(store.load().isEmpty)  // a missing file is empty, not an error

    let first = record(daysAgo: 1, score: 4200)
    try store.append(first)
    try store.append(record(daysAgo: 0, score: 6100))

    let loaded = store.load()
    #expect(loaded.count == 2)
    #expect(loaded.first == first)
    #expect(Statistics(records: loaded).bestScore == 6100)
}

@Test func anUnreadableHistoryIsNeverOverwritten() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("twist-tests-\(UUID().uuidString)")
        .appendingPathComponent("history.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)

    let store = HistoryStore(fileURL: url)
    #expect(store.load().isEmpty)
    // The unreadable file must survive the read — clobbering it destroys the only copy.
    #expect(FileManager.default.contents(atPath: url.path) == Data("not json".utf8))
}

@Test func aRecordSummarisesAFinishedSession() {
    let lexicon = Lexicon(
        entries: [
            LexiconEntry(word: "stream", isCommon: true),
            LexiconEntry(word: "steam", isCommon: true),
            LexiconEntry(word: "sea", isCommon: true),
        ],
        puzzles: [
            PuzzleSpec(rack: Signature("stream")!, difficulty: .gentle, commonWordCount: 3)
        ])
    var session = GameSession(
        lexicon: lexicon, settings: GameSettings(), generator: TwistRandom(seed: 1))!
    session.submit("stream")
    session.submit("sea")
    session.endRound()

    let record = GameRecord(session: session, finishedAt: Date())
    #expect(record.wordsFound == 2)
    #expect(record.bingosFound == 1)
    #expect(record.roundsCleared == 1)
    #expect(record.rackSizes == [6])
    #expect(record.wasTimed)
    #expect(record.score == session.bankedScore)
}

@Test func clearingRemovesTheHistoryFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("twist-tests-\(UUID().uuidString)")
        .appendingPathComponent("history.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = HistoryStore(fileURL: url)
    try store.append(record(daysAgo: 0, score: 5000))
    #expect(store.load().count == 1)

    try store.clear()
    #expect(store.load().isEmpty)
    // Gone, not emptied — nothing left to half-read.
    #expect(!FileManager.default.fileExists(atPath: url.path))

    // Clearing an already-clear history is not an error, and a later game still records.
    try store.clear()
    try store.append(record(daysAgo: 0, score: 100))
    #expect(store.load().count == 1)
}
