import Testing
@testable import TwistKit

@Test func anagramsShareASignature() {
    #expect(Signature("listen") == Signature("silent"))
    #expect(Signature("LISTEN") == Signature("silent"))
    #expect(Signature("listen") != Signature("listens"))
}

@Test func nonLettersHaveNoSignature() {
    #expect(Signature("can't") == nil)
    #expect(Signature("well-known") == nil)
    #expect(Signature("café") == nil)
    #expect(Signature("") == nil)
}

@Test func signatureLettersAreSorted() {
    #expect(Signature("twist")?.letters == "isttw")
}

@Test func subsignaturesCollapseRepeatedLetters() throws {
    let distinct = try #require(Signature("twist"))
    // Five letters, two of them the same: 2^5 - 1 = 31 masks, but the two `t`s make
    // several masks produce identical bags.
    #expect(distinct.subsignatures().count == 23)

    let noRepeats = try #require(Signature("crop"))
    #expect(noRepeats.subsignatures().count == 15)
}

@Test func subsignaturesRespectMinimumLength() throws {
    let rack = try #require(Signature("crop"))
    let threePlus = rack.subsignatures(minimumLength: 3)
    #expect(threePlus.count == 5)  // four 3-letter bags, one 4-letter bag
    #expect(threePlus.allSatisfy { $0.count >= 3 })
    #expect(threePlus.contains(try #require(Signature("crop"))))
}

@Test func subsignaturesIncludeRealWords() throws {
    let rack = try #require(Signature("stream"))
    let bags = rack.subsignatures(minimumLength: 3)
    for word in ["masters", "master", "steam", "tears", "rest", "sea", "art"] {
        let signature = try #require(Signature(word))
        #expect(bags.contains(signature) == (word.count <= 6), "\(word)")
    }
}

@Test func containmentIsBagwise() throws {
    let rack = try #require(Signature("letter"))  // e, e, l, r, t, t
    #expect(try #require(Signature("tree")).isContained(in: rack))
    #expect(try #require(Signature("eel")).isContained(in: rack))
    #expect(try #require(Signature("letter")).isContained(in: rack))
    // Only one `l` and two `t`s are available.
    #expect(!(try #require(Signature("teller")).isContained(in: rack)))
    #expect(!(try #require(Signature("tetter")).isContained(in: rack)))
    #expect(!(try #require(Signature("letters")).isContained(in: rack)))
}
