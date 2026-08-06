import Testing
@testable import TwistKit

private func entry(_ word: String, common: Bool = true) -> LexiconEntry {
    LexiconEntry(word: word, isCommon: common)
}

private func spec(_ rack: String, _ difficulty: Difficulty, _ count: Int) -> PuzzleSpec {
    PuzzleSpec(rack: Signature(rack)!, difficulty: difficulty, commonWordCount: count)
}

private let sampleEntries = [
    entry("stream"), entry("master"), entry("steam"), entry("tears"),
    entry("rest"), entry("sea"), entry("art"), entry("ares", common: false),
]
private let samplePuzzles = [spec("stream", .steady, 7), spec("crop", .brutal, 3)]

@Test func lexiconFindsEverySpellableWord() {
    let lexicon = Lexicon(entries: sampleEntries, puzzles: samplePuzzles)
    let found = Set(lexicon.words(spellableFrom: Signature("stream")!).map(\.word))
    #expect(found == ["stream", "master", "steam", "tears", "rest", "sea", "art", "ares"])
}

@Test func lexiconHonoursTheMinimumLength() {
    let lexicon = Lexicon(entries: sampleEntries + [entry("at")], puzzles: samplePuzzles)
    let found = Set(lexicon.words(spellableFrom: Signature("stream")!, minimumLength: 4).map(\.word))
    #expect(found == ["stream", "master", "steam", "tears", "rest", "ares"])
}

@Test func lexiconDistinguishesAnagramsOfTheSameBag() {
    let lexicon = Lexicon(entries: sampleEntries, puzzles: samplePuzzles)
    #expect(lexicon.entry(for: "master")?.word == "master")
    #expect(lexicon.entry(for: "MASTER")?.word == "master")
    #expect(lexicon.entry(for: "stream")?.word == "stream")
    // Same signature as `stream`, but not a word in this lexicon.
    #expect(lexicon.entry(for: "tamers") == nil)
    #expect(lexicon.entry(for: "nonsense") == nil)
}

@Test func lexiconReportsCommonness() {
    let lexicon = Lexicon(entries: sampleEntries, puzzles: samplePuzzles)
    #expect(lexicon.entry(for: "sea")?.isCommon == true)
    #expect(lexicon.entry(for: "ares")?.isCommon == false)
}

@Test func fileFormatRoundTrips() throws {
    let encoded = LexiconFile.encode(entries: sampleEntries, puzzles: samplePuzzles)
    let decoded = try LexiconFile.decode(encoded)

    #expect(decoded.wordCount == sampleEntries.count)
    #expect(Set(decoded.puzzles) == Set(samplePuzzles))
    #expect(decoded.entry(for: "ares")?.isCommon == false)
    #expect(decoded.entry(for: "stream")?.isCommon == true)
}

@Test func fileFormatRejectsAMissingHeader() {
    #expect(throws: LexiconFile.DecodingError.self) {
        try LexiconFile.decode("something else\nwords 0\npuzzles 0\n")
    }
    #expect(throws: LexiconFile.DecodingError.self) {
        try LexiconFile.decode("")
    }
}

@Test func fileFormatRejectsATruncatedSection() {
    // Claims three words, supplies one. Silently accepting this would ship a lexicon with
    // words missing and no indication anything was wrong.
    let truncated = """
        \(LexiconFile.header)
        words 3
        stream\t1
        puzzles 0
        """
    #expect(throws: LexiconFile.DecodingError.self) {
        try LexiconFile.decode(truncated)
    }
}

@Test func puzzlesFilterByRackSize() throws {
    let lexicon = Lexicon(entries: sampleEntries, puzzles: samplePuzzles)
    #expect(lexicon.puzzles(rackSize: 6).map(\.rack.letters) == ["aemrst"])
    #expect(lexicon.puzzles(rackSize: 4).map(\.rack.letters) == ["copr"])
    #expect(lexicon.puzzles(rackSize: 5).isEmpty)
}
