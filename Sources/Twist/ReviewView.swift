import SwiftUI
import TwistKit

/// The between-rounds screen — and the thing the original never had.
///
/// Text Twist told you only that you had failed. Showing what was actually on the board is
/// where the game stops being a test and starts teaching you racks.
struct ReviewView: View {
    let model: GameModel

    private var summary: RoundSummary? { model.reviewSummary }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            missedWords
            Divider()
            footer
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(width: 520, height: 560)
        .background(Theme.background)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(headline)
                .font(.title2.weight(.semibold))
            Text(model.round.puzzle.rack.letters.uppercased())
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(Theme.accent)

            if let summary {
                HStack(spacing: 24) {
                    Stat("Words", "\(summary.foundWords.count)")
                    Stat("Score", summary.score.formatted())
                    if summary.bonus > 0 {
                        Stat("Bonus", "+\(summary.bonus.formatted())")
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var headline: String {
        guard let summary else { return "Round over" }
        if summary.completed { return "Every word found" }
        if summary.foundBingo { return "Round cleared" }
        return "Out of time"
    }

    @ViewBuilder
    private var missedWords: some View {
        if let summary, !summary.missedWords.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("^[\(summary.missedWords.count) word](inflect: true) you missed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                ScrollIfNeeded {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(summary.missedWords, id: \.self) { word in
                            Text(word.uppercased())
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.slot))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.positive)
                Text("Nothing left on the board.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Button("New Game") { model.restart() }
            Spacer()
            if model.canContinue {
                Button("Next Round") { model.advance() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("A word using every letter is needed to go on.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .controlSize(.large)
        .padding(20)
    }
}

private struct Stat: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
