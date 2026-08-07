import Combine
import SwiftUI
import TwistKit

struct GameView: View {
    @Bindable var model: GameModel
    var onQuit: () -> Void = {}
    @FocusState private var boardFocused: Bool
    @State private var showingStats = false

    var body: some View {
        VStack(spacing: 0) {
            ScoreBar(model: model)
            Divider()
            // The curtain covers the board *and* the rack. Hiding only the word slots would
            // still leave the letters on screen with the clock stopped, which is the whole
            // anagram to work out at leisure. Nothing below the score bar survives a pause.
            ZStack {
                VStack(spacing: 0) {
                    WordBoard(model: model)
                    Divider()
                    PlayArea(model: model)
                }
                PausedCurtain(model: model)
            }
        }
        .background(Theme.background)
        // The whole window is the keyboard target — there is no text field to lose focus to.
        .focusable()
        .focusEffectDisabled()
        .focused($boardFocused)
        .onKeyPress(action: handle)
        .onAppear { boardFocused = true }
        .sheet(isPresented: .constant(model.isReviewing)) {
            ReviewView(model: model)
        }
        .sheet(isPresented: .constant(model.isFinished)) {
            GameOverView(model: model, onQuit: onQuit)
        }
        .sheet(isPresented: $showingStats) {
            StatsView(history: model.history)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showStatistics)) { _ in
            // Pause here rather than at the button, so the menu item and the shortcut stop the
            // clock too. Reading your stats should never cost you the round.
            model.pause()
            showingStats = true
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard !model.isReviewing else { return .ignored }
        switch press.key {
        case .return, .init(Character("\u{3}")):  // Return and numeric-keypad Enter
            model.submit()
        case .delete, .deleteForward:
            model.backspace()
        case .escape:
            model.clear()
        case "p" where press.modifiers.contains(.command):
            model.togglePause()
        case .space:
            model.twist()
        default:
            guard let character = press.characters.first, character.isLetter else {
                return .ignored
            }
            model.type(character)
        }
        return .handled
    }
}

// MARK: - Score bar

private struct ScoreBar: View {
    let model: GameModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text("Round \(model.session.roundNumber)")
            } icon: {
                Image(systemName: "square.grid.2x2")
            }
            .labelStyle(.titleAndIcon)

            Text(String(describing: model.round.puzzle.difficulty).capitalized)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.accentSoft, in: Capsule())

            Spacer()

            if let seconds = model.secondsRemaining {
                TimerLabel(seconds: seconds, isPaused: model.isPaused)
            } else {
                Label("Untimed", systemImage: "infinity")
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                model.togglePause()
            } label: {
                Label(
                    model.isPaused ? "Resume" : "Pause",
                    systemImage: model.isPaused ? "play.fill" : "pause.fill")
            }
            .help(model.isPaused ? "Resume (\u{2318}P)" : "Pause the clock (\u{2318}P)")

            Button {
                NotificationCenter.default.post(name: .showStatistics, object: nil)
            } label: {
                Label("Stats", systemImage: "chart.bar.fill")
            }
            .help("Scores, streaks and recent games (\u{21E7}\u{2318}T)")

            Spacer()

            Text(model.session.score, format: .number)
                .font(.title2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy, value: model.session.score)
                .accessibilityLabel("Score")
        }
        .font(.callout)
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }
}

private struct TimerLabel: View {
    let seconds: Int
    var isPaused = false

    private var isUrgent: Bool { seconds <= 15 && !isPaused }

    var body: some View {
        Label {
            Text("\(seconds / 60):\(seconds % 60, format: .number.precision(.integerLength(2)))")
                .monospacedDigit()
        } icon: {
            Image(systemName: isPaused ? "pause.circle" : "timer")
        }
        .opacity(isPaused ? 0.5 : 1)
        .font(.callout.weight(isUrgent ? .bold : .regular))
        .foregroundStyle(isUrgent ? Theme.urgent : Theme.textPrimary)
        .accessibilityLabel("\(seconds) seconds remaining")
    }
}

// MARK: - Word board

/// The slots for every common word the rack spells, grouped by length — the original's main
/// piece of guidance, and still the reason the game is solvable rather than a memory test.
private struct WordBoard: View {
    let model: GameModel

    // Seven-letter racks reach five length groups and can exceed the window, which pushed the
    // score bar and the controls off screen. A six-letter rack still fits without scrolling at
    // the minimum window size; this is the safety valve for the tall ones.
    var body: some View {
        ScrollIfNeeded {
            VStack(alignment: .leading, spacing: 16) {
            ForEach(model.round.commonWordsByLength, id: \.length) { group in
                VStack(alignment: .leading, spacing: 7) {
                    Text("^[\(group.length) letter](inflect: true)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    FlowLayout(spacing: 7, lineSpacing: 7) {
                        ForEach(group.words, id: \.word) { entry in
                            WordSlot(
                                word: entry.word,
                                isFound: model.round.hasFound(entry.word)
                            )
                        }
                    }
                }
            }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WordSlot: View {
    let word: String
    let isFound: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(isFound ? word.uppercased() : String(repeating: "·", count: word.count))
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(isFound ? Theme.accent : Theme.textFaint)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFound ? Theme.accentSoft : Theme.slot)
            )
            .scaleEffect(isFound ? 1 : 0.97)
            .animation(reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0.08), value: isFound)
            .accessibilityLabel(isFound ? word : "unfound \(word.count) letter word")
    }
}

/// Covers the board while paused, so stopping the clock cannot double as free study time.
private struct PausedCurtain: View {
    let model: GameModel

    var body: some View {
        if model.isPaused {
            ZStack {
                Rectangle().fill(Theme.background)
                VStack(spacing: 14) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                    Text("Paused")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Clock stopped. Board and rack hidden.")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    Button("Resume") { model.togglePause() }
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 4)
                }
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Play area

private struct PlayArea: View {
    let model: GameModel
    @Namespace private var tiles

    var body: some View {
        VStack(spacing: 14) {
            FeedbackLine(feedback: model.feedback)
            InputLine(word: model.typedWord, rackSize: model.round.puzzle.rackSize, namespace: tiles)
            Rack(model: model, namespace: tiles)
            PrimaryActions(model: model)
            UtilityBar(model: model)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }
}

private struct FeedbackLine: View {
    let feedback: GameModel.Feedback

    var body: some View {
        Group {
            switch feedback {
            case .none:
                Text(" ")
            case .accepted(let word, let points, let isBingo):
                Text("\(word.uppercased())  +\(points)\(isBingo ? "  ·  full rack!" : "")")
                    .foregroundStyle(Theme.positive)
            case .repeated(let word):
                Text("Already found \(word.uppercased())").foregroundStyle(Theme.textSecondary)
            case .rejected(let reason):
                Text(reason).foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.callout.weight(.medium))
        .frame(height: 20)
        .accessibilityLiveRegion()
    }
}

private struct InputLine: View {
    let word: String
    let rackSize: Int
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<rackSize, id: \.self) { index in
                let letters = Array(word)
                if index < letters.count {
                    TileView(letter: letters[index], role: .entry)
                        .matchedGeometryEffect(id: "entry-\(index)", in: namespace)
                } else {
                    TileView(letter: nil, role: .empty)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.isEmpty ? "No letters entered" : "Entered \(word)")
    }
}

private struct Rack: View {
    let model: GameModel
    let namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(model.round.tiles.enumerated()), id: \.offset) { index, letter in
                let isStaged = model.typedTileIndices.contains(index)
                TileView(
                    letter: letter,
                    role: isStaged ? .staged : .rack,
                    action: isStaged ? nil : { model.stage(tileAt: index) }
                )
                .accessibilityLabel(
                    isStaged ? "Tile used" : "Tile \(String(letter).uppercased())")
                .accessibilityAddTraits(isStaged ? [] : .isButton)
            }
        }
        // Keyed on the rack itself, so a twist animates the letters into their new places
        // rather than cross-fading them.
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: model.round.tiles)
    }
}

/// Enter and Twist, centred directly beneath the rack.
private struct PrimaryActions: View {
    let model: GameModel

    var body: some View {
        HStack(spacing: 12) {
            Button("Enter") { model.submit() }
                .buttonStyle(PrimaryButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
                .help("Submit the word (Return)")
            Button("Twist") { model.twist() }
                .buttonStyle(PrimaryButtonStyle())
                .help("Shuffle the rack (Space)")
        }
        .pointerStyle(.link)
    }
}

/// Everything you reach for rarely: clearing, the two toggles, and ending the round.
///
/// Separated from Twist and Enter so the constant actions and the occasional ones do not sit
/// in one undifferentiated row — and so Give Up is nowhere near Enter, where a mis-click would
/// end the round.
private struct UtilityBar: View {
    let model: GameModel

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("Appearance") private var appearance: Appearance = .dark

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: 10) {
            Button("Clear") { model.clear() }
                .help("Clear what you have typed (Escape)")

            Spacer()

            Button {
                model.isSoundEnabled.toggle()
            } label: {
                Image(systemName: model.isSoundEnabled ? "speaker.wave.2" : "speaker.slash")
            }
            .buttonStyle(IconButtonStyle())
            .help(model.isSoundEnabled ? "Mute" : "Unmute")
            .accessibilityLabel("Sound")

            // Flips straight between light and dark off the resolved scheme, so it does the
            // obvious thing even when the setting is currently Follow System. The three-way
            // choice stays in View > Appearance.
            Button {
                appearance = isDark ? .light : .dark
            } label: {
                Image(systemName: isDark ? "sun.max" : "moon")
            }
            .buttonStyle(IconButtonStyle())
            .help(isDark ? "Switch to light" : "Switch to dark")
            .accessibilityLabel(isDark ? "Switch to light appearance" : "Switch to dark appearance")

            Button(model.session.settings.secondsPerRound == nil ? "End Round" : "Give Up") {
                model.endRound()
            }
            .frame(minHeight: 32)
            .help("Finish this round and see what you missed")
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
        .pointerStyle(.link)
    }
}

extension View {
    /// Announces changes to VoiceOver without stealing focus.
    func accessibilityLiveRegion() -> some View {
        accessibilityAddTraits(.updatesFrequently)
    }
}


extension Notification.Name {
    /// Bridges the Statistics menu command to the window showing the game.
    static let showStatistics = Notification.Name("net.crews.twist.showStatistics")
}
