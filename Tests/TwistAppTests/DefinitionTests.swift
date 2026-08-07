import Foundation
import Testing

@testable import Twist

/// The parser, not the dictionary. Raw entries are fed in verbatim so these assertions hold on
/// any machine — the real lookup's content varies by OS and locale, which is the whole reason
/// `DefinitionProvider` is a protocol.

@Test func aFullEntryIsReducedToOneSense() {
    let raw = "scone | skōn, skän | noun a small unsweetened or lightly sweetened biscuit-like "
        + "cake made from flour, fat, and milk: a cream tea with scones."
    let d = SystemDefinitionProvider.parse(raw, lookedUp: "scone")
    #expect(d?.headword == "scone")
    #expect(d?.partOfSpeech == "noun")
    #expect(d?.text == "a small unsweetened or lightly sweetened biscuit-like cake made from flour, fat, and milk")
}

@Test func theHeadwordFoundCanDifferFromTheWordLookedUp() {
    // Looking up an inflection returns the base entry, and saying so is informative.
    let raw = "eon e·on | ˈēən | noun an indefinite and very long period of time"
    let d = SystemDefinitionProvider.parse(raw, lookedUp: "eons")
    #expect(d?.headword == "eon")
    #expect(d?.text == "an indefinite and very long period of time")
}

@Test func onlyTheFirstSenseIsKept() {
    let raw = "brig | briɡ | noun 1 a two-masted square-rigged ship 2 a prison on a warship"
    let d = SystemDefinitionProvider.parse(raw, lookedUp: "brig")
    #expect(d?.text == "a two-masted square-rigged ship")
}

@Test func aVeryLongSenseIsCutAtAWordBoundary() {
    let long = String(repeating: "verylongish ", count: 40)
    let d = SystemDefinitionProvider.parse("thing | θɪŋ | noun \(long)", lookedUp: "thing")
    let text = try! #require(d?.text)
    #expect(text.count <= 244)
    #expect(text.hasSuffix("…"))
    #expect(!text.contains("verylongi…"))  // cut between words, never mid-word
}

@Test func anEntryWithNothingUsableYieldsNil() {
    #expect(SystemDefinitionProvider.parse("", lookedUp: "x") == nil)
    #expect(SystemDefinitionProvider.parse("word | wərd | noun ", lookedUp: "word") == nil)
}

@Test func theStubAnswersOnlyWhatItWasGiven() {
    let stub = StubDefinitionProvider(entries: [
        "scone": Definition(headword: "scone", partOfSpeech: "noun", text: "a small cake")
    ])
    #expect(stub.definition(for: "SCONE")?.text == "a small cake")   // case-insensitive
    #expect(stub.definition(for: "acne") == nil)
}
