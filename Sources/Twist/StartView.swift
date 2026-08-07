import SwiftUI
import TwistKit

/// The screen the app opens on.
///
/// It exists for two reasons. Dropping straight into a running two-minute clock gives you no
/// moment to settle before the game is already costing you time. And the clock and rack-size
/// choices had nowhere to live — `GameSettings` has supported untimed play and single-size
/// racks all along with no way for a player to pick either.
struct StartView: View {
    @Bindable var app: AppModel
    @State private var showingStats = false

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("Appearance") private var appearance: Appearance = .dark

    private var isTimed: Bool { app.settings.secondsPerRound != nil }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Text("TWIST")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .tracking(10)
                    .foregroundStyle(Theme.accent)
                Text("Find every word in the letters.")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(spacing: 22) {
                choice(
                    title: "Clock",
                    options: [("2:00", true), ("Untimed", false)],
                    isSelected: { $0 == isTimed },
                    select: { timed in
                        app.settings.clock = timed ? .timed(seconds: 120) : .untimed
                    })

                choice(
                    title: "Letters",
                    options: [("6", Set([6])), ("7", Set([7])), ("Both", Set([6, 7]))],
                    isSelected: { $0 == app.settings.rackSizes },
                    select: { app.settings.rackSizes = $0 })
            }
            .padding(.top, 40)

            Button {
                app.startGame()
            } label: {
                Text("Start Game")
                    .font(.title3.weight(.semibold))
                    .frame(width: 240, height: 52)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 40)

            if app.statistics.gamesPlayed > 0 {
                // Separate Text views rather than one concatenated string: the ^[…](inflect:)
                // markup is only honoured inside a single literal, and building the line with
                // + printed the markup verbatim.
                HStack(spacing: 8) {
                    Text("Best \(app.statistics.bestScore.formatted())")
                    Text("·")
                    Text("^[\(app.statistics.gamesPlayed) game](inflect: true)")
                    if app.statistics.currentStreak > 1 {
                        Text("·")
                        Text("\(app.statistics.currentStreak)-day streak")
                    }
                }
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 18)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("Statistics") { showingStats = true }
                    .disabled(app.history.isEmpty)
                Spacer()
                Button {
                    appearance = colorScheme == .dark ? .light : .dark
                } label: {
                    Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                        .frame(width: 22, height: 22)
                }
                .help(colorScheme == .dark ? "Switch to light" : "Switch to dark")
                .accessibilityLabel("Appearance")
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .pointerStyle(.link)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .sheet(isPresented: $showingStats) {
            StatsView(history: app.history)
        }
    }

    /// A labelled row of mutually exclusive options, sized for a trackpad rather than a mouse.
    private func choice<Value: Equatable>(
        title: String,
        options: [(String, Value)],
        isSelected: @escaping (Value) -> Bool,
        select: @escaping (Value) -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let selected = isSelected(option.1)
                    Button {
                        select(option.1)
                    } label: {
                        Text(option.0)
                            .font(.body.weight(selected ? .semibold : .regular))
                            .frame(minWidth: 92, minHeight: 44)
                            .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Theme.accentSoft : Theme.slot))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selected ? Theme.accent.opacity(0.6) : Theme.hairline,
                                        lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}
