/// A canonical, order-independent identity for a bag of letters.
///
/// Two words are anagrams of each other exactly when their signatures are equal, so a
/// `[Signature: [String]]` map turns "which words can this rack spell" into a handful of
/// dictionary probes.
public struct Signature: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The letters, lowercased and sorted. `"listen"` and `"silent"` both give `"eilnst"`.
    public let letters: String

    /// Non-nil only when every character is an ASCII letter. Words carrying apostrophes,
    /// hyphens, or diacritics have no signature and are not playable.
    public init?(_ word: some StringProtocol) {
        var scalars: [UInt8] = []
        scalars.reserveCapacity(word.count)
        for character in word.unicodeScalars {
            switch character.value {
            case 0x41...0x5A: scalars.append(UInt8(character.value) + 32)  // A-Z
            case 0x61...0x7A: scalars.append(UInt8(character.value))       // a-z
            default: return nil
            }
        }
        guard !scalars.isEmpty else { return nil }
        scalars.sort()
        self.letters = String(decoding: scalars, as: UTF8.self)
    }

    public var count: Int { letters.count }

    public var description: String { letters }

    public static func < (lhs: Signature, rhs: Signature) -> Bool {
        (lhs.count, lhs.letters) < (rhs.count, rhs.letters)
    }
}

extension Signature {
    /// Every distinct sub-bag of these letters with at least `minimumLength` letters,
    /// including the full bag itself.
    ///
    /// A rack of *n* letters has 2^n subsets, but repeated letters collapse many of them
    /// together — `"eeffort"` yields 96 distinct sub-bags rather than 128. At the seven-letter
    /// ceiling this is cheap enough to run on every keystroke if we wanted to.
    public func subsignatures(minimumLength: Int = 1) -> Set<Signature> {
        let characters = Array(letters)
        guard characters.count <= 16 else {
            preconditionFailure("subsignature enumeration is exponential; racks stay small")
        }

        var result = Set<Signature>()
        for mask in 1..<(1 << characters.count) {
            guard mask.nonzeroBitCount >= minimumLength else { continue }
            var subset = ""
            subset.reserveCapacity(mask.nonzeroBitCount)
            for index in characters.indices where mask & (1 << index) != 0 {
                subset.append(characters[index])
            }
            // `characters` is sorted, so `subset` is built in sorted order already.
            result.insert(Signature(unchecked: subset))
        }
        return result
    }

    /// Whether these letters can be spelled from `rack` without reusing a tile.
    public func isContained(in rack: Signature) -> Bool {
        var available = Array(rack.letters)
        for letter in letters {
            guard let index = available.firstIndex(of: letter) else { return false }
            available.remove(at: index)
        }
        return true
    }

    /// Bypasses validation and sorting for strings already known to be lowercase and sorted.
    init(unchecked letters: String) {
        self.letters = letters
    }
}
