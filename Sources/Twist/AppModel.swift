import Foundation
import Observation
import TwistKit

/// Owns what outlives a single game: the lexicon, the history, and the chosen mode.
///
/// A game is created when you press Start and released when you come back to the menu, so the
/// app no longer opens straight into a running clock.
@MainActor
@Observable
final class AppModel {
    let lexicon: Lexicon
    private let store: HistoryStore

    private(set) var game: GameModel?
    private(set) var history: [GameRecord]

    /// The mode the next game will use. Persisted, so the menu comes back the way you left it.
    var settings: GameSettings {
        didSet { persist(settings) }
    }

    var statistics: Statistics { Statistics(records: history) }

    init(lexicon: Lexicon, store: HistoryStore? = nil) {
        self.lexicon = lexicon
        self.store = store ?? HistoryStore(
            fileURL: (try? HistoryStore.defaultURL())
                ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("history.json"))
        self.history = self.store.load()
        self.settings = Self.restoredSettings()
    }

    // MARK: - Flow

    func startGame() {
        game = GameModel(lexicon: lexicon, settings: settings, store: store)
    }

    /// Drops the game and refreshes the history, so the menu shows the sitting just finished.
    func returnToMenu() {
        game = nil
        history = store.load()
    }

    /// Wipes every recorded game. Irreversible, so the UI confirms before calling it.
    func resetHistory() {
        try? store.clear()
        history = []
    }

    // MARK: - Persisted mode

    private static let clockKey = "ClockSeconds"  // 0 means untimed
    private static let rackKey = "RackSizes"

    private static func restoredSettings() -> GameSettings {
        let defaults = UserDefaults.standard
        let clock: GameSettings.Clock
        if let seconds = defaults.object(forKey: clockKey) as? Int {
            clock = seconds > 0 ? .timed(seconds: seconds) : .untimed
        } else {
            clock = .timed(seconds: 120)  // the original's two minutes
        }
        let sizes = (defaults.array(forKey: rackKey) as? [Int]).map(Set.init) ?? [6, 7]
        return GameSettings(clock: clock, rackSizes: sizes)
    }

    private func persist(_ settings: GameSettings) {
        UserDefaults.standard.set(settings.secondsPerRound ?? 0, forKey: Self.clockKey)
        UserDefaults.standard.set(settings.rackSizes.sorted(), forKey: Self.rackKey)
    }
}
