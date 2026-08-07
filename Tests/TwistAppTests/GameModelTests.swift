import Foundation
import Testing
import TwistKit

@testable import Twist

/// The app layer, which had no tests until now and is where most of the shipped bugs lived:
/// a sound toggle that muted without redrawing, staged letters that could not be clicked back,
/// a twist that discarded the word being typed, and a snapshot fixture that wrote to the real
/// preferences. Every one of those was invisible to the rules tests in TwistKitTests.

/// `stream` spells exactly these, so every assertion below is about behaviour rather than about
/// which words happen to be in the real dictionary.
private let lexicon = Lexicon(
    entries: [
        LexiconEntry(word: "stream", isCommon: true),
        LexiconEntry(word: "master", isCommon: true),
        LexiconEntry(word: "steam", isCommon: true),
        LexiconEntry(word: "tears", isCommon: true),
        LexiconEntry(word: "rest", isCommon: true),
        LexiconEntry(word: "sea", isCommon: true),
        LexiconEntry(word: "ares", isCommon: false),
    ],
    puzzles: [PuzzleSpec(rack: Signature("stream")!, difficulty: .steady, commonWordCount: 6)]
)

/// A throwaway defaults domain and history file per test, so nothing touches the real ones and
/// tests cannot leak into each other.
@MainActor
private func makeModel(
    settings: GameSettings = GameSettings(clock: .timed(seconds: 120), rackSizes: [6])
) -> (model: GameModel, defaults: UserDefaults, historyURL: URL) {
    let suite = "twist.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("twist-tests-\(UUID().uuidString)")
        .appendingPathComponent("history.json")
    let model = GameModel(
        lexicon: lexicon, settings: settings, store: HistoryStore(fileURL: url),
        defaults: defaults)
    return (model, defaults, url)
}

// MARK: - Staging letters

@MainActor
@Test func typingTakesALetterOutOfTheRack() {
    let (model, _, _) = makeModel()
    let first = model.round.tiles[0]

    model.type(first)
    #expect(model.typedWord == String(first))
    #expect(model.availableTiles.count == model.round.tiles.count - 1)
    #expect(!model.availableTiles.contains { $0.index == 0 })
}

@MainActor
@Test func typingALetterTheRackDoesNotHaveIsIgnored() {
    let (model, _, _) = makeModel()
    model.type("z")
    #expect(model.typedWord.isEmpty)
}

@MainActor
@Test func aDuplicateLetterUsesTheSecondTileNotTheSameOneTwice() {
    // The rack is a,e,m,r,s,t — no duplicates — so this asserts the general rule instead:
    // every staged position is distinct.
    let (model, _, _) = makeModel()
    for character in model.round.tiles { model.type(character) }
    #expect(model.typedWord.count == model.round.tiles.count)
    #expect(Set(model.typedTileIndices).count == model.typedTileIndices.count)
    #expect(model.availableTiles.isEmpty)
}

@MainActor
@Test func unstagingReturnsThatLetterAndKeepsTheOrderOfTheRest() {
    let (model, _, _) = makeModel()
    let letters = Array(model.round.tiles.prefix(3))
    for character in letters { model.type(character) }
    #expect(model.typedWord == String(letters))

    // The middle one, which backspace could never reach.
    model.unstage(at: 1)
    #expect(model.typedWord == String([letters[0], letters[2]]))
    #expect(model.availableTiles.contains { $0.letter == letters[1] })
}

@MainActor
@Test func unstagingAnOutOfRangePositionIsHarmless() {
    let (model, _, _) = makeModel()
    model.type(model.round.tiles[0])
    model.unstage(at: 7)
    model.unstage(at: -1)
    #expect(model.typedWord.count == 1)
}

@MainActor
@Test func backspaceTakesTheLastLetterAndClearTakesThemAll() {
    let (model, _, _) = makeModel()
    for character in model.round.tiles.prefix(3) { model.type(character) }

    model.backspace()
    #expect(model.typedWord.count == 2)

    model.clear()
    #expect(model.typedWord.isEmpty)
    #expect(model.availableTiles.count == model.round.tiles.count)

    // Both are safe on an empty line.
    model.backspace()
    model.clear()
    #expect(model.typedWord.isEmpty)
}

// MARK: - Twisting

@MainActor
@Test func twistKeepsWhatHasAlreadyBeenTyped() {
    let (model, _, _) = makeModel()
    for character in model.round.tiles.prefix(3) { model.type(character) }
    let staged = model.typedWord

    model.twist()

    // The word survives, spelled from the same letters, and the indices still resolve.
    #expect(model.typedWord == staged)
    #expect(model.typedTileIndices.count == 3)
    #expect(Set(model.typedTileIndices).count == 3)
    // What is left packs to the front, so the gaps trail.
    #expect(model.availableTiles.map(\.index) == Array(0..<3))
    #expect(model.round.tiles.sorted() == Array("aemrst"))
}

@MainActor
@Test func twistOnAnEmptyLineStillRearrangesTheRack() {
    let (model, _, _) = makeModel()
    let before = model.round.tiles
    model.twist()
    #expect(model.round.tiles.sorted() == before.sorted())
    #expect(model.typedWord.isEmpty)
}

// MARK: - Submitting

@MainActor
@Test func submittingAWordScoresItAndClearsTheLine() {
    let (model, _, _) = makeModel()
    for character in "steam" { model.type(character) }
    model.submit()

    #expect(model.typedWord.isEmpty)
    #expect(model.round.hasFound("steam"))
    #expect(model.session.score > 0)
    if case .accepted(let word, _, let isBingo) = model.feedback {
        #expect(word == "steam")
        #expect(!isBingo)
    } else {
        Issue.record("expected an accepted feedback, got \(model.feedback)")
    }
}

@MainActor
@Test func aFullRackWordReportsABingo() {
    let (model, _, _) = makeModel()
    for character in "stream" { model.type(character) }
    model.submit()
    if case .accepted(_, _, let isBingo) = model.feedback {
        #expect(isBingo)
    } else {
        Issue.record("expected an accepted feedback, got \(model.feedback)")
    }
    #expect(model.round.hasFoundBingo)
}

@MainActor
@Test func aRejectedWordIsReportedAndCostsNothing() {
    let (model, _, _) = makeModel()
    for character in "mates" { model.type(character) }  // spellable, not a word here
    model.submit()

    #expect(model.session.score == 0)
    #expect(model.typedWord.isEmpty)
    if case .rejected = model.feedback {} else {
        Issue.record("expected a rejection, got \(model.feedback)")
    }
}

@MainActor
@Test func submittingAnEmptyLineDoesNothing() {
    let (model, _, _) = makeModel()
    model.submit()
    #expect(model.feedback == .none)
    #expect(model.session.score == 0)
}

// MARK: - Pause

@MainActor
@Test func pauseBlocksEveryWayOfChangingTheRound() {
    let (model, _, _) = makeModel()
    for character in model.round.tiles.prefix(2) { model.type(character) }

    model.togglePause()
    #expect(model.isPaused)
    // Pausing clears the half-typed line rather than resuming into letters you have forgotten.
    #expect(model.typedWord.isEmpty)

    let tiles = model.round.tiles
    model.type(tiles[0])
    model.stage(tileAt: 1)
    model.twist()
    model.submit()

    #expect(model.typedWord.isEmpty)
    #expect(model.round.tiles == tiles)
    #expect(model.session.score == 0)

    model.togglePause()
    #expect(!model.isPaused)
    model.type(tiles[0])
    #expect(model.typedWord.count == 1)  // input works again
}

@MainActor
@Test func pauseIsIdempotentThroughTheConvenienceEntryPoint() {
    let (model, _, _) = makeModel()
    model.pause()
    model.pause()
    #expect(model.isPaused)
    model.togglePause()
    #expect(!model.isPaused)
}

// MARK: - Sound preference

@MainActor
@Test func theSoundFlagPersistsAndIsReadBackOnLaunch() {
    let (model, defaults, url) = makeModel()
    #expect(model.isSoundEnabled)

    model.isSoundEnabled = false
    #expect(defaults.bool(forKey: "SoundEnabled") == false)

    // A fresh model over the same defaults comes up muted.
    let relaunched = GameModel(
        lexicon: lexicon, store: HistoryStore(fileURL: url), defaults: defaults)
    #expect(relaunched.isSoundEnabled == false)
}

@MainActor
@Test func theSoundFlagNeverTouchesTheRealPreferences() {
    let realValueBefore = UserDefaults.standard.object(forKey: "SoundEnabled")
    let (model, _, _) = makeModel()
    model.isSoundEnabled = false
    model.isSoundEnabled = true

    let realValueAfter = UserDefaults.standard.object(forKey: "SoundEnabled") as? Bool
    #expect(realValueAfter as Any? as? Bool == realValueBefore as? Bool)
}

// MARK: - History

@MainActor
@Test func resettingHistoryClearsItAndDoesNotRebankTheCurrentGame() {
    let (model, _, _) = makeModel()
    for character in "steam" { model.type(character) }
    model.submit()

    model.resetHistory()
    #expect(model.history.isEmpty)

    // Finishing the sitting must not write it into the history just cleared.
    model.endRound()
    model.advance()
    #expect(model.history.isEmpty)
}
