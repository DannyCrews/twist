import Foundation
import TwistKit

let outputURL = URL(fileURLWithPath: "Sources/Twist/Resources/lexicon.twist")

func run() async throws {
    switch CommandLine.arguments.dropFirst().first ?? "build" {
    case "build": try await build()
    case "stats": try await stats()
    case "verify": try verify()
    case "sample": try sample()
    case let other:
        throw Failure("unknown command '\(other)'; expected build, stats, or verify")
    }
}

// MARK: - build

func build() async throws {
    async let enable = loadEnable()
    async let subtlex = loadFrequencies()
    let (words, frequencies) = try await (enable, subtlex)
    let result = buildLexicon(words: words, frequencies: frequencies)

    let text = LexiconFile.encode(entries: result.entries, puzzles: result.puzzles)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: outputURL, atomically: true, encoding: .utf8)

    let common = result.entries.count(where: \.isCommon)
    print("""
        wrote \(outputURL.path) (\(text.utf8.count.formatted(.byteCount(style: .file))))
          words     \(result.entries.count.formatted()) accepted, \(common.formatted()) common
          puzzles   \(result.puzzles.count.formatted())
        """)
    for size in [6, 7] {
        let bucket = result.puzzles.filter { $0.rackSize == size }
        let byDifficulty = Difficulty.allCases
            .map { difficulty in "\(difficulty): \(bucket.count { $0.difficulty == difficulty })" }
            .joined(separator: "  ")
        print("          \(size)-letter \(bucket.count.formatted()) — \(byDifficulty)")
    }
    print("""
          rejected  \(result.skippedUncommonBingo.formatted()) racks with no common bingo word
                    \(result.skippedBands.values.reduce(0, +).formatted()) racks outside the \
        \(Tuning.commonWordBand.lowerBound)–\(Tuning.commonWordBand.upperBound) common-word band
        """)
}

// MARK: - stats

/// Reports the distributions the Tuning constants were picked against, so re-tuning is a
/// measurement rather than a guess.
func stats() async throws {
    async let enable = loadEnable()
    async let subtlex = loadFrequencies()
    let (words, frequencies) = try await (enable, subtlex)

    print("ENABLE: \(words.count.formatted()) words, SUBTLEX: \(frequencies.count.formatted()) entries")

    print("\ncommon-word count by SUBTLEX threshold (ENABLE words of 3–7 letters):")
    let playable = words.filter { Tuning.wordLengths.contains($0.count) }
    for threshold in [1, 5, 10, 20, 50, 100, 500] {
        let kept = playable.count { (frequencies[$0] ?? 0) >= threshold }
        let share = Double(kept) / Double(playable.count) * 100
        print("  >= \(threshold, format: 4): \(kept, format: 7) of \(playable.count.formatted()) (\(share.formatted(.number.precision(.fractionLength(1))))%)")
    }

    print("\nracks per band, at the current threshold of \(Tuning.commonThreshold):")
    let result = buildLexicon(words: words, frequencies: frequencies)
    let counts = result.puzzles.map(\.commonWordCount).sorted()
    if !counts.isEmpty {
        let median = counts[counts.count / 2]
        print("  kept \(result.puzzles.count.formatted()) racks, common-word count \(counts.first!)–\(counts.last!), median \(median)")
    }
}

// MARK: - verify

/// Asserts the invariants the game relies on, and reports what the artifact costs to load.
func verify() throws {
    guard FileManager.default.fileExists(atPath: outputURL.path) else {
        throw Failure("\(outputURL.path) does not exist — run `dicttool build` first")
    }

    let start = ContinuousClock.now
    let text = try String(contentsOf: outputURL, encoding: .utf8)
    let lexicon = try LexiconFile.decode(text)
    let elapsed = ContinuousClock.now - start

    var problems: [String] = []

    if lexicon.puzzles.isEmpty { problems.append("puzzle pool is empty") }

    for size in [6, 7] where lexicon.puzzles(rackSize: size).isEmpty {
        problems.append("no \(size)-letter racks")
    }
    for difficulty in Difficulty.allCases
    where !lexicon.puzzles.contains(where: { $0.difficulty == difficulty }) {
        problems.append("no racks in difficulty \(difficulty)")
    }

    for puzzle in lexicon.puzzles {
        let solutions = lexicon.words(spellableFrom: puzzle.rack)

        // The bingo word must exist and be findable.
        let bingo = solutions.filter { $0.word.count == puzzle.rackSize }
        if bingo.isEmpty {
            problems.append("\(puzzle.rack): no word uses all \(puzzle.rackSize) letters")
        } else if Tuning.bingoMustBeCommon && !bingo.contains(where: \.isCommon) {
            problems.append("\(puzzle.rack): no common bingo word")
        }

        // The recorded target must match what the lexicon actually yields, or the completion
        // bonus becomes unreachable.
        let actual = solutions.count(where: \.isCommon)
        if actual != puzzle.commonWordCount {
            problems.append("\(puzzle.rack): recorded \(puzzle.commonWordCount) common words, found \(actual)")
        }

        if problems.count > 20 { break }
    }

    print("""
        loaded \(lexicon.wordCount.formatted()) words and \(lexicon.puzzles.count.formatted()) racks \
        in \(elapsed.formattedMilliseconds)
        """)

    guard problems.isEmpty else {
        for problem in problems.prefix(20) { print("  FAIL \(problem)") }
        throw Failure("\(problems.count) invariant failure(s)")
    }
    print("  all invariants hold")
}

// MARK: - sample

/// Prints a handful of racks with their solutions, so the common/uncommon split can be judged
/// by eye. Tuning constants that look reasonable in the aggregate can still produce rounds that
/// play badly, and this is the cheapest way to notice.
func sample() throws {
    let lexicon = try LexiconFile.decode(try String(contentsOf: outputURL, encoding: .utf8))
    // Deterministic pick: evenly spaced through the pool, so reruns are comparable.
    let sorted = lexicon.puzzles.sorted { $0.rack < $1.rack }
    let wanted = 8
    let stride = max(1, sorted.count / wanted)

    for puzzle in Swift.stride(from: 0, to: sorted.count, by: stride).prefix(wanted).map({ sorted[$0] }) {
        let solutions = lexicon.words(spellableFrom: puzzle.rack)
            .sorted { ($0.word.count, $0.word) > ($1.word.count, $1.word) }
        let common = solutions.filter(\.isCommon).map(\.word)
        let rare = solutions.filter { !$0.isCommon }.map(\.word)

        print("\n\(puzzle.rack.letters.uppercased())  [\(puzzle.difficulty)]  target \(puzzle.commonWordCount)")
        print("  common (\(common.count)): \(common.joined(separator: " "))")
        print("  rare   (\(rare.count)): \(rare.prefix(18).joined(separator: " "))\(rare.count > 18 ? " …" : "")")
    }
}

extension Duration {
    var formattedMilliseconds: String {
        let milliseconds = Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1e15
        return "\(milliseconds.formatted(.number.precision(.fractionLength(1))))ms"
    }
}

extension String.StringInterpolation {
    /// Right-aligns an integer so the stats tables line up.
    mutating func appendInterpolation(_ value: Int, format width: Int) {
        appendLiteral(String(repeating: " ", count: max(0, width - "\(value)".count)) + "\(value)")
    }
}

do {
    try await run()
} catch {
    FileHandle.standardError.write(Data("dicttool: \(error)\n".utf8))
    exit(1)
}
