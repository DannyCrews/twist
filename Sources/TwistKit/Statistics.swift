import Foundation

/// A finished sitting, recorded for the history.
public struct GameRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var finishedAt: Date
    public var score: Int
    public var roundsCleared: Int
    public var roundsCompleted: Int
    public var wordsFound: Int
    public var bingosFound: Int
    public var rackSizes: [Int]
    public var wasTimed: Bool

    public init(
        id: UUID = UUID(),
        finishedAt: Date,
        score: Int,
        roundsCleared: Int,
        roundsCompleted: Int,
        wordsFound: Int,
        bingosFound: Int,
        rackSizes: [Int],
        wasTimed: Bool
    ) {
        self.id = id
        self.finishedAt = finishedAt
        self.score = score
        self.roundsCleared = roundsCleared
        self.roundsCompleted = roundsCompleted
        self.wordsFound = wordsFound
        self.bingosFound = bingosFound
        self.rackSizes = rackSizes
        self.wasTimed = wasTimed
    }

    /// Builds a record from a finished session.
    public init(session: GameSession, finishedAt: Date) {
        let rounds = session.completedRounds
        self.init(
            finishedAt: finishedAt,
            score: session.bankedScore,
            roundsCleared: rounds.count(where: \.foundBingo),
            roundsCompleted: rounds.count(where: \.completed),
            wordsFound: rounds.reduce(0) { $0 + $1.foundWords.count },
            bingosFound: rounds.count(where: \.foundBingo),
            rackSizes: rounds.map(\.rack.count),
            wasTimed: session.settings.secondsPerRound != nil
        )
    }
}

/// Lifetime totals, derived from the history rather than stored alongside it — one source of
/// truth, and no counter that can drift out of step with the games behind it.
public struct Statistics: Equatable, Sendable {
    public let gamesPlayed: Int
    public let bestScore: Int
    public let totalScore: Int
    public let wordsFound: Int
    public let bingosFound: Int
    public let roundsCleared: Int
    public let longestStreak: Int
    public let currentStreak: Int

    public var averageScore: Int {
        gamesPlayed == 0 ? 0 : totalScore / gamesPlayed
    }

    public init(records: [GameRecord]) {
        gamesPlayed = records.count
        bestScore = records.map(\.score).max() ?? 0
        totalScore = records.reduce(0) { $0 + $1.score }
        wordsFound = records.reduce(0) { $0 + $1.wordsFound }
        bingosFound = records.reduce(0) { $0 + $1.bingosFound }
        roundsCleared = records.reduce(0) { $0 + $1.roundsCleared }

        // A streak is consecutive calendar days with at least one game, counted back from the
        // most recent day played.
        let days = Set(records.map { Calendar.current.startOfDay(for: $0.finishedAt) }).sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, Calendar.current.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        longestStreak = longest

        // The current streak only counts if the run reaches today or yesterday; an older run
        // has already been broken.
        let today = Calendar.current.startOfDay(for: Date())
        if let last = days.last,
            let gap = Calendar.current.dateComponents([.day], from: last, to: today).day,
            gap <= 1
        {
            currentStreak = run
        } else {
            currentStreak = 0
        }
    }

    /// Best score per rack size, for the per-size breakdown.
    public static func bestScores(byRackSize records: [GameRecord]) -> [Int: Int] {
        var best: [Int: Int] = [:]
        for record in records {
            // A mixed-size sitting counts toward every size it actually dealt.
            for size in Set(record.rackSizes) {
                best[size] = max(best[size] ?? 0, record.score)
            }
        }
        return best
    }
}
