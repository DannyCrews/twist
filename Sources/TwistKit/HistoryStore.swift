import Foundation

/// Persists the game history as JSON in Application Support.
///
/// Deliberately not SwiftData: this is a single-user local list that only ever grows at the
/// end, and a schema-migration system would be pure overhead against a file you can read with
/// `cat` when something looks wrong.
public struct HistoryStore: Sendable {
    public let fileURL: URL

    /// `~/Library/Application Support/Twist/history.json`.
    public static func defaultURL(
        bundleName: String = "Twist", fileManager: FileManager = .default
    ) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return support.appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [GameRecord] {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A history that cannot be read is not worth crashing over, and not worth silently
        // overwriting either — return nothing and leave the file alone for inspection.
        return (try? decoder.decode([GameRecord].self, from: data)) ?? []
    }

    public func save(_ records: [GameRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func append(_ record: GameRecord) throws -> [GameRecord] {
        var records = load()
        records.append(record)
        try save(records)
        return records
    }
}
