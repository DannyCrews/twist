import Foundation
import Observation
import TwistKit

/// The app's mutable game state: a `GameSession`, the letters currently typed, and the clock.
///
/// Every rule lives in TwistKit. This owns only what a running app needs on top of it — which
/// tiles are spoken for, how much time is left, and what just happened so the UI can react.
@MainActor
@Observable
final class GameModel {
    enum Feedback: Equatable {
        case none
        case accepted(word: String, points: Int, isBingo: Bool)
        case rejected(reason: String)
        case repeated(word: String)
    }

    private(set) var session: GameSession
    private(set) var lexicon: Lexicon

    /// Every finished sitting, newest last. Kept in memory and mirrored to disk.
    private(set) var history: [GameRecord]
    private let store: HistoryStore

    /// Guards against banking the same sitting twice — a game can finish by running out of
    /// racks and then be replaced by New Game, and both paths want to record it.
    private var hasRecordedSession = false

    /// Indices into `session.round.tiles` for the letters staged in the input line, in the
    /// order they were typed. Indices rather than characters, so a rack with two `E`s consumes
    /// a specific tile and the other stays available.
    private(set) var typedTileIndices: [Int] = []

    private(set) var secondsRemaining: Int?

    /// Paused stops the clock and hides the board. Hiding matters: without it, pausing is a
    /// way to study the words with the timer stopped, which only cheats the player.
    private(set) var isPaused = false
    private(set) var feedback: Feedback = .none

    private var clockTask: Task<Void, Never>?
    private let sound = SoundEngine()

    /// Injected so the snapshot tool can write preferences into a throwaway domain. Writing to
    /// `.standard` there meant rendering the muted fixture silently muted the real game.
    private let defaults: UserDefaults

    /// Sound is on by default and remembered between launches.
    ///
    /// Stored here rather than computed through to `SoundEngine`: `@Observable` only tracks
    /// stored properties, so a computed forwarder muted the audio correctly while leaving the
    /// button's icon frozen on its old state — working, and indistinguishable from broken.
    var isSoundEnabled: Bool = true {
        didSet {
            sound.isEnabled = isSoundEnabled
            defaults.set(isSoundEnabled, forKey: "SoundEnabled")
        }
    }

    init(
        lexicon: Lexicon,
        settings: GameSettings = GameSettings(rackSizes: [6, 7]),
        store: HistoryStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.lexicon = lexicon
        self.defaults = defaults
        self.store = store ?? HistoryStore(
            fileURL: (try? HistoryStore.defaultURL())
                ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("history.json"))
        self.history = self.store.load()
        // The lexicon ships with the app and is verified at build time, so an empty pool is a
        // packaging failure rather than a runtime condition to design around.
        guard let session = GameSession(lexicon: lexicon, settings: settings) else {
            preconditionFailure("lexicon contains no playable racks")
        }
        self.session = session
        // didSet does not fire during init, so both sides are set explicitly.
        if defaults.object(forKey: "SoundEnabled") != nil {
            isSoundEnabled = defaults.bool(forKey: "SoundEnabled")
        }
        sound.isEnabled = isSoundEnabled
        startClock()
    }

    // No deinit cancelling `clockTask`: a main-actor property cannot be touched from a
    // nonisolated deinit. The clock holds `self` weakly and returns once it is gone.

    // MARK: - Derived state

    var round: Round { session.round }

    var typedWord: String {
        String(typedTileIndices.map { round.tiles[$0] })
    }

    /// Tiles not currently staged in the input line, paired with their index in the rack.
    var availableTiles: [(index: Int, letter: Character)] {
        round.tiles.enumerated()
            .filter { !typedTileIndices.contains($0.offset) }
            .map { (index: $0.offset, letter: $0.element) }
    }

    var isReviewing: Bool {
        if case .reviewing = session.state { return true }
        return false
    }

    var reviewSummary: RoundSummary? {
        if case .reviewing(let summary, _) = session.state { return summary }
        return nil
    }

    var canContinue: Bool {
        if case .reviewing(_, let canContinue) = session.state { return canContinue }
        return false
    }

    var isFinished: Bool { session.state == .finished }

    var statistics: Statistics { Statistics(records: history) }

    // MARK: - Input

    /// Stages a letter, consuming a matching rack tile. Ignored when no tile matches.
    func type(_ character: Character) {
        guard !isPaused else { return }
        let letter = Character(character.lowercased())
        guard let tile = availableTiles.first(where: { $0.letter == letter }) else { return }
        typedTileIndices.append(tile.index)
        feedback = .none
        sound.play(.tile)
    }

    /// Stages a specific tile, for clicking rather than typing.
    func stage(tileAt index: Int) {
        guard !isPaused else { return }
        guard round.tiles.indices.contains(index), !typedTileIndices.contains(index) else { return }
        typedTileIndices.append(index)
        feedback = .none
        sound.play(.tile)
    }

    /// Returns one staged letter to the rack, by its position in the typed word.
    ///
    /// Backspace only ever removed the last letter, so fixing the first letter of a six-letter
    /// word meant clearing the whole line and retyping it.
    func unstage(at position: Int) {
        guard !isPaused, typedTileIndices.indices.contains(position) else { return }
        typedTileIndices.remove(at: position)
        feedback = .none
        sound.play(.tile)
    }

    func backspace() {
        guard !typedTileIndices.isEmpty else { return }
        typedTileIndices.removeLast()
        feedback = .none
    }

    func clear() {
        typedTileIndices.removeAll()
        feedback = .none
    }

    func submit() {
        guard !isPaused else { return }
        let word = typedWord
        guard !word.isEmpty else { return }

        let wasComplete = round.isComplete
        switch session.submit(word) {
        case .accepted(let word, let points, let isBingo):
            feedback = .accepted(word: word, points: points, isBingo: isBingo)
            sound.play(isBingo ? .bingo : .word)
        case .alreadyFound(let word):
            feedback = .repeated(word: word)
            sound.play(.reject)
        case .tooShort:
            feedback = .rejected(reason: "Three letters or more")
            sound.play(.reject)
        case .notSpellableFromRack:
            feedback = .rejected(reason: "Not in the rack")
            sound.play(.reject)
        case .notAWord:
            feedback = .rejected(reason: "Not a word")
            sound.play(.reject)
        }
        // The chord belongs to clearing the board, so it fires on the transition only.
        if !wasComplete && round.isComplete {
            sound.play(.roundComplete)
        }
        typedTileIndices.removeAll()
    }

    /// Shuffles the rack. Staged letters are returned to it first — their indices would
    /// otherwise point at different tiles.
    func twist() {
        guard !isPaused else { return }
        typedTileIndices.removeAll()
        session.twist()
        feedback = .none
        sound.play(.twist)
    }

    /// Pausing clears anything half-typed, so resuming starts from a clean line rather than
    /// from letters you no longer remember choosing.
    func togglePause() {
        guard !isReviewing, !isFinished else { return }
        isPaused.toggle()
        if isPaused {
            typedTileIndices.removeAll()
            feedback = .none
        }
    }

    func pause() {
        if !isPaused { togglePause() }
    }

    // MARK: - Round flow

    func endRound() {
        stopClock()
        isPaused = false
        typedTileIndices.removeAll()
        feedback = .none
        session.endRound()
    }

    func advance() {
        guard session.advance() else {
            recordSession()
            return
        }
        isPaused = false
        typedTileIndices.removeAll()
        feedback = .none
        startClock()
    }

    func restart(settings: GameSettings? = nil) {
        stopClock()
        recordSession()
        guard let fresh = GameSession(lexicon: lexicon, settings: settings ?? session.settings)
        else { return }
        session = fresh
        hasRecordedSession = false
        isPaused = false
        typedTileIndices.removeAll()
        feedback = .none
        startClock()
    }

    /// Banks the sitting into the history. A sitting with no finished round is not a game.
    private func recordSession() {
        guard !hasRecordedSession, !session.completedRounds.isEmpty else { return }
        hasRecordedSession = true

        let record = GameRecord(session: session, finishedAt: Date())
        history.append(record)
        // A failed write costs the history entry, not the game in progress.
        try? store.save(history)
    }

    // MARK: - Clock

    private func startClock() {
        stopClock()
        guard let limit = session.settings.secondsPerRound else {
            secondsRemaining = nil
            return
        }
        secondsRemaining = limit
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.isPaused { continue }
                guard let remaining = self.secondsRemaining, remaining > 0 else { return }
                self.secondsRemaining = remaining - 1
                // One soft low note at ten seconds. Not a countdown tick — being ticked at is
                // the opposite of what this game is for.
                if self.secondsRemaining == 10 {
                    self.sound.play(.timeLow)
                }
                if self.secondsRemaining == 0 {
                    self.endRound()
                    return
                }
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }
}
