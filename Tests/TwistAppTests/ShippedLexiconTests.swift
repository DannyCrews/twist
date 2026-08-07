import Foundation
import Testing
import TwistKit

@testable import Twist

/// Tests against the word list that actually ships, not a fixture.
///
/// Everything else in the suite proves the rules are right. These prove the *data* is right,
/// which is a separate failure mode and the one that produced the worst bug in this project:
/// the board dealing ethnic slurs as words it asked the player to find. No rules test could
/// have caught that, because the rules were working perfectly.
struct ShippedLexicon {
    static let lexicon = LexiconLoader.loadBundled()
}

@Test func theBundledLexiconLoads() {
    let lexicon = ShippedLexicon.lexicon
    // 38,183 after the cull, down from 51,733: words WordNet does not know and speech barely
    // uses are gone. The floor is well below that so ordinary tuning does not trip it, but high
    // enough to catch a build that silently produced almost nothing.
    #expect(lexicon.wordCount > 30_000)
    #expect(lexicon.puzzles.count > 4_000)
    for size in [6, 7] {
        #expect(!lexicon.puzzles(rackSize: size).isEmpty, "no \(size)-letter racks")
    }
    for difficulty in Difficulty.allCases {
        #expect(
            lexicon.puzzles.contains { $0.difficulty == difficulty },
            "no racks at difficulty \(difficulty)")
    }
}

@Test func noBlockedWordSurvivedIntoTheShippedLexicon() throws {
    // Read the same file dicttool builds from, so the test cannot drift from the source of
    // truth by being given its own hand-copied list.
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TwistAppTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Sources/dicttool/blocklist.txt")
    let text = try String(contentsOf: url, encoding: .utf8)

    let blocked = text.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    #expect(blocked.count > 20, "blocklist looks empty — is the path still right?")

    let lexicon = ShippedLexicon.lexicon
    let survivors = blocked.filter { lexicon.entry(for: $0) != nil }
    #expect(survivors.isEmpty, "blocked words are still playable: \(survivors.sorted())")
}

@Test func everyRackCanBeFinished() {
    // The bingo word is the gate on advancing, so a rack without a findable one is unplayable.
    // Sampled rather than exhaustive: the full pass lives in `dicttool verify`, which the
    // Makefile runs alongside these tests.
    let lexicon = ShippedLexicon.lexicon
    let racks = lexicon.puzzles.sorted { $0.rack < $1.rack }
    let step = max(1, racks.count / 400)
    var checked = 0

    for puzzle in stride(from: 0, to: racks.count, by: step).map({ racks[$0] }) {
        let solutions = lexicon.words(spellableFrom: puzzle.rack)
        let bingos = solutions.filter { $0.word.count == puzzle.rackSize }
        // Hoisted out of #expect: the macro cannot expand a rethrows call inline.
        let hasCommonBingo = bingos.contains { $0.isCommon }
        #expect(!bingos.isEmpty, "\(puzzle.rack): nothing uses all the letters")
        #expect(hasCommonBingo, "\(puzzle.rack): no common bingo word")

        // The recorded target has to match what the lexicon yields, or clearing the board
        // becomes impossible and the completion bonus unreachable.
        let commonCount = solutions.count { $0.isCommon }
        #expect(
            commonCount == puzzle.commonWordCount,
            "\(puzzle.rack): target \(puzzle.commonWordCount) does not match the lexicon")
        checked += 1
    }
    #expect(checked >= 300)
}

@Test func racksAreSolvableWithoutBeingTrivial() {
    let lexicon = ShippedLexicon.lexicon
    let counts = lexicon.puzzles.map(\.commonWordCount)
    // A rack with two words is over before it starts; one with ninety is a slog.
    #expect(counts.allSatisfy { $0 >= 6 && $0 <= 45 })
}

@Test func theLexiconLoadsFastEnoughToNotDelayLaunch() {
    let start = ContinuousClock.now
    _ = LexiconLoader.loadBundled()
    let elapsed = ContinuousClock.now - start
    // Generous against a debug build; the point is to catch a change that makes loading
    // pathological, not to benchmark.
    #expect(elapsed < .milliseconds(1500), "lexicon took \(elapsed) to load")
}
