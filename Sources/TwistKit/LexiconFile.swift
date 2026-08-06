import Foundation

/// Reads and writes the artifact the offline pipeline produces and the app ships.
///
/// The format is line-oriented text: it compresses well, diffs legibly, and parses fast enough
/// that a binary layout would buy nothing measurable at this size. `dicttool build --time`
/// reports the actual load cost.
///
///     twist-lexicon 1
///     words <count>
///     <word>\t<0|1 common>
///     ...
///     puzzles <count>
///     <signature>\t<difficulty>\t<commonWordCount>
///     ...
public enum LexiconFile {
    static let header = "twist-lexicon 1"

    public enum DecodingError: Error, CustomStringConvertible {
        case badHeader(String)
        case badSection(expected: String, found: String)
        case badCount(String)
        case truncated(section: String, expected: Int, found: Int)
        case badRecord(section: String, line: String)

        public var description: String {
            switch self {
            case .badHeader(let found):
                "expected header '\(LexiconFile.header)', found '\(found)'"
            case .badSection(let expected, let found):
                "expected section '\(expected)', found '\(found)'"
            case .badCount(let found):
                "unreadable record count '\(found)'"
            case .truncated(let section, let expected, let found):
                "\(section): expected \(expected) records, found \(found)"
            case .badRecord(let section, let line):
                "\(section): malformed record '\(line)'"
            }
        }
    }

    public static func encode(entries: [LexiconEntry], puzzles: [PuzzleSpec]) -> String {
        var output = "\(header)\n"
        output += "words \(entries.count)\n"
        for entry in entries.sorted(by: { $0.word < $1.word }) {
            output += "\(entry.word)\t\(entry.isCommon ? 1 : 0)\n"
        }
        output += "puzzles \(puzzles.count)\n"
        for puzzle in puzzles.sorted(by: { $0.rack < $1.rack }) {
            output += "\(puzzle.rack.letters)\t\(puzzle.difficulty.rawValue)\t\(puzzle.commonWordCount)\n"
        }
        return output
    }

    public static func decode(_ text: String) throws -> Lexicon {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).makeIterator()

        let first = lines.next()
        guard let first, first == header else {
            throw DecodingError.badHeader(first.map(String.init) ?? "<empty file>")
        }

        let entries = try decodeSection(named: "words", from: &lines) {
            (fields: [Substring]) -> LexiconEntry? in
            guard fields.count == 2, let common = Int(fields[1]) else { return nil }
            return LexiconEntry(word: String(fields[0]), isCommon: common == 1)
        }

        let puzzles = try decodeSection(named: "puzzles", from: &lines) {
            (fields: [Substring]) -> PuzzleSpec? in
            guard fields.count == 3,
                  let rack = Signature(fields[0]),
                  let raw = UInt8(fields[1]),
                  let difficulty = Difficulty(rawValue: raw),
                  let commonCount = Int(fields[2])
            else { return nil }
            return PuzzleSpec(rack: rack, difficulty: difficulty, commonWordCount: commonCount)
        }

        return Lexicon(entries: entries, puzzles: puzzles)
    }

    private static func decodeSection<Record>(
        named name: String,
        from lines: inout Array<Substring>.Iterator,
        parse: ([Substring]) -> Record?
    ) throws -> [Record] {
        guard let heading = lines.next() else {
            throw DecodingError.badSection(expected: name, found: "end of file")
        }
        let parts = heading.split(separator: " ")
        guard parts.count == 2, parts[0] == name else {
            throw DecodingError.badSection(expected: name, found: String(heading))
        }
        guard let count = Int(parts[1]), count >= 0 else {
            throw DecodingError.badCount(String(parts[1]))
        }

        var records: [Record] = []
        records.reserveCapacity(count)
        while records.count < count {
            guard let line = lines.next() else {
                throw DecodingError.truncated(section: name, expected: count, found: records.count)
            }
            guard let record = parse(line.split(separator: "\t", omittingEmptySubsequences: false))
            else {
                throw DecodingError.badRecord(section: name, line: String(line))
            }
            records.append(record)
        }
        return records
    }
}
