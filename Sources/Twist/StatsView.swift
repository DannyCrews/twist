import SwiftUI
import TwistKit

/// End of a sitting: what it was worth, and where it sits against everything before it.
struct GameOverView: View {
    let model: GameModel

    private var lastGame: GameRecord? { model.history.last }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Game over")
                    .font(.largeTitle.weight(.semibold))
                Text("^[\(model.session.completedRounds.count) round](inflect: true) played")
                    .foregroundStyle(.secondary)
            }

            Text(model.session.bankedScore, format: .number)
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())

            let best = model.statistics.bestScore
            if best > 0 {
                let isBest = lastGame.map { $0.score >= best } ?? false
                Text(isBest ? "Your best yet" : "Best \(best.formatted())")
                    .font(.callout)
                    .foregroundStyle(isBest ? Theme.accent : Theme.textSecondary)
            }

            StatsGrid(statistics: model.statistics, history: model.history)
                .padding(.top, 4)

            Button("New Game") { model.restart() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(32)
        .foregroundStyle(Theme.textPrimary)
        .frame(width: 480)
        .background(Theme.background)
    }
}

/// Lifetime totals, reachable at any time from the menu.
struct StatsView: View {
    let model: GameModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Statistics")
                .font(.title2.weight(.semibold))

            if model.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Finish a game and it will show up here.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                StatsGrid(statistics: model.statistics, history: model.history)
                RecentGames(records: model.history)
            }

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .foregroundStyle(Theme.textPrimary)
        .frame(width: 460, height: 520)
        .background(Theme.background)
    }
}

// MARK: - Pieces

private struct StatsGrid: View {
    let statistics: Statistics
    let history: [GameRecord]

    private var bestBySize: [Int: Int] { Statistics.bestScores(byRackSize: history) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                Cell("Games", statistics.gamesPlayed.formatted())
                Cell("Best", statistics.bestScore.formatted())
                Cell("Average", statistics.averageScore.formatted())
            }
            HStack(spacing: 0) {
                Cell("Words", statistics.wordsFound.formatted())
                Cell("Streak", statistics.currentStreak.formatted())
                Cell("Longest", statistics.longestStreak.formatted())
            }
            if !bestBySize.isEmpty {
                HStack(spacing: 0) {
                    ForEach(bestBySize.keys.sorted(), id: \.self) { size in
                        Cell("Best on \(size)", (bestBySize[size] ?? 0).formatted())
                    }
                    // Pad to three columns so this row lines up with the two above it.
                    ForEach(bestBySize.count..<3, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    private struct Cell: View {
        let label: String
        let value: String

        init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }

        var body: some View {
            VStack(spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct RecentGames: View {
    let records: [GameRecord]

    private var recent: [GameRecord] { records.suffix(6).reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent games")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            ScrollIfNeeded {
                VStack(spacing: 0) {
                    ForEach(recent) { record in
                        HStack {
                            Text(record.finishedAt, format: .dateTime.month().day())
                                .foregroundStyle(Theme.textSecondary)
                            Text("^[\(record.roundsCleared) round](inflect: true)")
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(record.score, format: .number)
                                .monospacedDigit()
                        }
                        .font(.callout)
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
