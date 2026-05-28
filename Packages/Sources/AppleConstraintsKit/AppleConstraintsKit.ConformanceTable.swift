import Foundation
import SearchModels

extension AppleConstraintsKit {
    /// Codable on-disk + in-memory representation of the symbol-graph
    /// conformance table (`apple-conformances.json`). Conforms to
    /// `Search.StaticConformancesLookup` so the composition root can inject it
    /// as a protocol value without the SearchSQLite enrichment pass importing
    /// AppleConstraintsKit. Conformance sibling of `AppleConstraintsKit.Table`.
    ///
    /// **JSON-on-disk shape.**
    /// ```json
    /// {
    ///   "schemaVersion": 1,
    ///   "entries": [
    ///     {"conformsTo": ["View","Equatable"], "docURI": "apple-docs://swiftui/foreach"},
    ///     ...
    ///   ]
    /// }
    /// ```
    public struct ConformanceTable: Codable, Sendable, Search.StaticConformancesLookup {
        public let schemaVersion: Int
        public let entries: [Search.StaticConformanceEntry]

        public static let currentSchemaVersion: Int = 1

        public init(
            schemaVersion: Int = Self.currentSchemaVersion,
            entries: [Search.StaticConformanceEntry]
        ) {
            self.schemaVersion = schemaVersion
            self.entries = entries
        }

        public func allConformanceEntries() async throws -> [Search.StaticConformanceEntry] {
            entries
        }
    }
}

extension AppleConstraintsKit.ConformanceTable {
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public static func from(jsonData data: Data) throws -> AppleConstraintsKit.ConformanceTable {
        let decoded = try JSONDecoder().decode(AppleConstraintsKit.ConformanceTable.self, from: data)
        guard decoded.schemaVersion <= currentSchemaVersion else {
            throw LoadError.schemaVersionTooNew(
                onDisk: decoded.schemaVersion,
                binaryUnderstands: currentSchemaVersion
            )
        }
        return decoded
    }

    public static func from(fileURL: URL) throws -> AppleConstraintsKit.ConformanceTable {
        try from(jsonData: Data(contentsOf: fileURL))
    }

    public enum LoadError: Swift.Error, Sendable, Equatable {
        case schemaVersionTooNew(onDisk: Int, binaryUnderstands: Int)
    }
}
