import Foundation

extension Search {
    /// One row of the installed-source inventory: a per-source database, whether its file is
    /// present on disk, and the schema version read from it. Reported by the `list_sources` MCP
    /// tool so clients (cupertino-desktop#92/#98) can detect a missing or partial corpus and
    /// guide setup, instead of scanning the filesystem and hardcoding filenames.
    public struct SourceInventoryItem: Codable, Equatable, Sendable {
        /// The database/descriptor id (e.g. `apple-documentation`, `swift-evolution`); the
        /// on-disk identity, matching the filename stem.
        public let id: String
        /// The routing/source id used to scope queries (`source:` in `search`,
        /// `list_documents`, `list_children`), e.g. `apple-docs` for the `apple-documentation`
        /// database. This is the source's `SourceDefinition.id`; a consumer maps it to its own
        /// source model without hardcoding a descriptor-id ↔ source-id table. Equals `id` for
        /// every source except apple-docs (`apple-docs` vs `apple-documentation`) and sample
        /// code (`samples` vs `apple-sample-code`). Additive field (since v1.3.x); older clients
        /// ignore it. Foundational enabler for the deferred query-side pluggability work
        /// (`docs/design/query-side-source-pluggability.md`).
        public let sourceID: String
        /// Human-readable name (e.g. `Apple Developer Documentation`).
        public let displayName: String
        /// The on-disk database filename (e.g. `apple-documentation.db`).
        public let filename: String
        /// Whether the database file exists on disk.
        public let present: Bool
        /// The schema version read from the database (`0` when absent or unreadable).
        public let schemaVersion: Int

        public init(id: String, sourceID: String, displayName: String, filename: String, present: Bool, schemaVersion: Int) {
            self.id = id
            self.sourceID = sourceID
            self.displayName = displayName
            self.filename = filename
            self.present = present
            self.schemaVersion = schemaVersion
        }
    }

    /// The canonical inventory of the active per-source databases (the "8 sources" model, derived
    /// from the source registry so it excludes the legacy unified `search.db` and stays correct
    /// across the per-source-DB-split migration). `expected` is how many sources the registry
    /// declares; `installed` is how many of those files are present.
    public struct SourceInventory: Codable, Equatable, Sendable {
        public let sources: [SourceInventoryItem]

        public init(sources: [SourceInventoryItem]) {
            self.sources = sources
        }

        /// The number of sources the registry declares (the canonical count, e.g. 8).
        public var expected: Int {
            sources.count
        }

        /// The number of declared sources whose database file is present on disk.
        public var installed: Int {
            sources.lazy.filter(\.present).count
        }

        /// Whether every declared source's database is present.
        public var isComplete: Bool {
            installed == expected
        }
    }
}
