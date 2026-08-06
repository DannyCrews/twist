import Combine
import SwiftUI
import TwistKit

struct GameView: View {
    @Bindable var model: GameModel
    @FocusState private var boardFocused: Bool
    @State private var showingStats = false

    var body: some View {
        VStack(spacing: 0) {
            ScoreBar(model: model)
            Divider()
            WordBoard(model: model)
            Divider()
            PlayArea(model: model)
        }
        .background(.background)
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
            GameOverView(model: model)
        }
        .sheet(isPresented: $showingStats) {
            StatsView(model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showStatistics)) { _ in
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
                .background(.quaternary, in: Capsule())

            Spacer()

            if let seconds = model.secondsRemaining {
                TimerLabel(seconds: seconds)
            } else {
                Label("Untimed", systemImage: "infinity")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(model.session.score, format: .number)
                .font(.title2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy, value: model.session.score)
                .accessibilityLabel("Score")
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct TimerLabel: View {
    let seconds: Int

    private var isUrgent: Bool { seconds <= 15 }

    var body: some View {
        Label {
            Text("\(seconds / 60):\(seconds % 60, format: .number.precision(.integerLength(2)))")
                .monospacedDigit()
        } icon: {
            Image(systemName: "timer")
        }
        .font(.callout.weight(isUrgent ? .bold : .regular))
        .foregroundStyle(isUrgent ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        .accessibilityLabel("\(seconds) seconds remaining")
    }
}

// MARK: - Word board

/// The slots for every common word the rack spells, grouped by length — the original's main
/// piece of guidance, and still the reason the game is solvable rather than a memory test.
private struct WordBoard: View {
    let model: GameModel

    // No ScrollView: a rack tops out at 45 common words, which fits, and hiding words below a
    // fold during a timed round would be the wrong trade even if it did not.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(model.round.commonWordsByLength, id: \.length) { group in
                VStack(alignment: .leading, spacing: 7) {
                    Text("^[\(group.length) letter](inflect: true)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

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
            .foregroundStyle(isFound ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFound ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)))
            )
            .scaleEffect(isFound ? 1 : 0.97)
            .animation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.2), value: isFound)
            .accessibilityLabel(isFound ? word : "unfound \(word.count) letter word")
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
            Controls(model: model)
        }
        .padding(20)
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
                    .foregroundStyle(.green)
            case .repeated(let word):
                Text("Already found \(word.uppercased())").foregroundStyle(.secondary)
            case .rejected(let reason):
                Text(reason).foregroundStyle(.secondary)
            }
        }
        .font(.callout.weight(.medium))
        .frame(height: 20)
        .animation(.snappy, value: feedback)
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

private struct Controls: View {
    let model: GameModel

    var body: some View {
        HStack(spacing: 12) {
            Button("Twist") { model.twist() }
                .help("Shuffle the rack (Space)")
            Button("Clear") { model.clear() }
                .help("Clear what you have typed (Escape)")
            Button("Enter") { model.submit() }
                .keyboardShortcut(.defaultAction)
                .help("Submit the word (Return)")

            Spacer()

            Toggle(isOn: Binding(get: { model.isSoundEnabled }, set: { model.isSoundEnabled = $0 })) {
                Image(systemName: model.isSoundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .frame(width: 22, height: 22)
            }
            .toggleStyle(.button)
            .help(model.isSoundEnabled ? "Mute" : "Unmute")
            .accessibilityLabel("Sound")

            Button(model.session.settings.secondsPerRound == nil ? "End Round" : "Give Up") {
                model.endRound()
            }
            .help("Finish this round and see what you missed")
        }
        .controlSize(.extraLarge)
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
