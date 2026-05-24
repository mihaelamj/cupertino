import Foundation
import SearchModels

extension AppleConstraintsKit {
    /// Codable on-disk + in-memory representation of the filtered
    /// constraint table. Conforms to `Search.StaticConstraintsLookup`
    /// so a binary can construct one and inject it into
    /// `Search.IndexBuilder` without crossing the
    /// AppleConstraintsKit-importing boundary in SearchAPI itself
    /// (rule 3. cross-target seam via protocol in Models).
    ///
    /// **JSON-on-disk shape.** Single top-level object with two
    /// fields:
    /// ```json
    /// {
    ///   "schemaVersion": 1,
    ///   "entries": [
    ///     {"docURI": "apple-docs://swiftui/foreach", "constraints": ["RandomAccessCollection","Hashable"]},
    ///     ...
    ///   ]
    /// }
    /// ```
    /// Schema version is bumped when the structure changes (e.g.
    /// adding a per-entry `signature` field for overload
    /// disambiguation). The cupertino indexer's loader rejects
    /// versions newer than it understands rather than guessing.
    ///
    /// **No Singleton** (rule 1). A `Table` is constructed from JSON
    /// at the composition root and threaded down as `any
    /// Search.StaticConstraintsLookup`. No `static let shared`.
    public struct Table: Codable, Sendable, Search.StaticConstraintsLookup {
        public let schemaVersion: Int
        public let entries: [Search.StaticConstraintEntry]

        public static let currentSchemaVersion: Int = 1

        public init(
            schemaVersion: Int = Self.currentSchemaVersion,
            entries: [Search.StaticConstraintEntry]
        ) {
            self.schemaVersion = schemaVersion
            self.entries = entries
        }

        // MARK: - Search.StaticConstraintsLookup conformance

        public func allEntries() async throws -> [Search.StaticConstraintEntry] {
            entries
        }
    }
}

extension AppleConstraintsKit.Table {
    /// Encode the table to compact JSON suitable for writing to disk.
    /// Keys are alphabetically sorted for stable diffs across
    /// regenerations (useful when the table lives in a git-tracked
    /// repo).
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    /// Read a table from JSON `Data`. Throws on malformed JSON or
    /// when the on-disk `schemaVersion` is newer than this binary
    /// understands (the indexer refuses to guess).
    public static func from(jsonData data: Data) throws -> AppleConstraintsKit.Table {
        let decoded = try JSONDecoder().decode(AppleConstraintsKit.Table.self, from: data)
        guard decoded.schemaVersion <= currentSchemaVersion else {
            throw LoadError.schemaVersionTooNew(
                onDisk: decoded.schemaVersion,
                binaryUnderstands: currentSchemaVersion
            )
        }
        return decoded
    }

    /// Read a table from a file URL. Same semantics as
    /// `from(jsonData:)` plus filesystem error wrapping.
    public static func from(fileURL: URL) throws -> AppleConstraintsKit.Table {
        let data = try Data(contentsOf: fileURL)
        return try from(jsonData: data)
    }

    public enum LoadError: Swift.Error, Sendable, Equatable {
        case schemaVersionTooNew(onDisk: Int, binaryUnderstands: Int)
    }
}
