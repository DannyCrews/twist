import Foundation
import TwistKit

/// Tuning for the lexicon build. Every number here changes how the game feels, so they live
/// together rather than scattered through the code. `dicttool stats` reports the distributions
/// these were chosen against.
enum Tuning {
    /// Racks are 6 or 7 tiles, and the shortest playable word is 3 letters, so nothing outside
    /// this range can ever appear.
    static let wordLengths = 3...7

    /// SUBTLEX occurrences, out of a 51-million-word corpus, for a word to count as common.
    /// Words below this still score if you find them; they just are not part of the target.
    static let commonThreshold = 20

    /// A word survives the cull if WordNet knows it, or if it clears this many SUBTLEX
    /// occurrences. Neither signal is sufficient alone: WordNet has no `bro`, `carbs` or
    /// `carpool`, and SUBTLEX has almost nothing for `antic`, `nit` or `scant`. Together they
    /// keep 38,182 words and drop 13,551 — `aal`, `abaka`, `abaxile`, `abmhos`, `abomasa` — the
    /// Scrabble-dictionary detritus that scores points nobody can look up.
    static let cullFrequencyFloor = 3

    /// A rack is only dealt if its bingo word is common — nobody enjoys being told the word
    /// they could not find was `retsina`.
    static let bingoMustBeCommon = true

    /// Racks spelling fewer common words than this are dull; more than this are exhausting.
    static let commonWordBand = 6...45

    /// Upper bound of each difficulty bucket, by common-word count. Fewer findable words is
    /// harder, so the buckets run from most words to fewest.
    static let difficultyCeilings: [(Difficulty, Int)] = [
        (.gentle, .max), (.steady, 24), (.tricky, 16), (.brutal, 10),
    ]

    static func difficulty(forCommonWordCount count: Int) -> Difficulty {
        // Ordered hardest-first so the tightest matching bucket wins.
        for (difficulty, ceiling) in difficultyCeilings.reversed() where count <= ceiling {
            return difficulty
        }
        return .gentle
    }
}

struct BuildResult {
    let entries: [LexiconEntry]
    let puzzles: [PuzzleSpec]
    let skippedBands: [Int: Int]  // rack size -> racks rejected for falling outside the band
    let skippedUncommonBingo: Int
    let blockedWords: Int
    let culledWords: Int
}

func buildLexicon(
    words: [String], frequencies: Frequencies, blocked: Set<String> = [],
    wordNet: WordNet? = nil
) -> BuildResult {
    // Accepted words: everything in ENABLE that a rack could physically spell, less anything
    // blocked. Blocked words are removed outright rather than merely demoted out of the common
    // tier — the game should not quietly award points for typing a slur either.
    var entries: [LexiconEntry] = []
    var signatureToEntries: [Signature: [LexiconEntry]] = [:]
    var blockedCount = 0
    var culledCount = 0
    for word in words where Tuning.wordLengths.contains(word.count) {
        guard let signature = Signature(word) else { continue }
        if blocked.contains(word) { blockedCount += 1; continue }

        let frequency = frequencies.count(word)
        let inWordNet = wordNet?.knows(word) ?? true

        // Real English, or common enough in speech that a 1990s lexical database missing it
        // says more about the database than the word.
        guard inWordNet || frequency >= Tuning.cullFrequencyFloor else {
            culledCount += 1
            continue
        }

        // Two ways to qualify as a board target, because neither alone is right.
        //
        // Real lowercase usage covers the closed-class words WordNet omits on principle —
        // requiring WordNet alone dropped `and`, `that`, `with`, `these`, `among` and `unless`
        // from the board, which is far worse than the proper nouns it excluded.
        //
        // WordNet covers the words SUBTLEX only ever sees capitalised because they usually
        // start a name: `saint`, `china`, `mark`, `bill`. It excludes `mae`, `nam` and `mel`,
        // which are equally capitalised but are not words.
        let usedLowercase = frequencies.lowercaseCount(word) >= Tuning.commonThreshold
        let entry = LexiconEntry(
            word: word,
            isCommon: frequency >= Tuning.commonThreshold && (usedLowercase || inWordNet)
        )
        entries.append(entry)
        signatureToEntries[signature, default: []].append(entry)
    }

    // Candidate racks: every distinct 6- and 7-letter bag of letters, deduplicated by
    // signature so `stream` and `masters` do not both become racks.
    var skippedBands: [Int: Int] = [:]
    var skippedUncommonBingo = 0
    var puzzles: [PuzzleSpec] = []

    for (signature, bingoEntries) in signatureToEntries where (6...7).contains(signature.count) {
        if Tuning.bingoMustBeCommon && !bingoEntries.contains(where: \.isCommon) {
            skippedUncommonBingo += 1
            continue
        }

        var commonCount = 0
        for subsignature in signature.subsignatures(minimumLength: Tuning.wordLengths.lowerBound) {
            for entry in signatureToEntries[subsignature] ?? [] where entry.isCommon {
                commonCount += 1
            }
        }

        guard Tuning.commonWordBand.contains(commonCount) else {
            skippedBands[signature.count, default: 0] += 1
            continue
        }

        puzzles.append(
            PuzzleSpec(
                rack: signature,
                difficulty: Tuning.difficulty(forCommonWordCount: commonCount),
                commonWordCount: commonCount
            ))
    }

    return BuildResult(
        entries: entries,
        puzzles: puzzles,
        skippedBands: skippedBands,
        skippedUncommonBingo: skippedUncommonBingo,
        blockedWords: blockedCount,
        culledWords: culledCount
    )
}
