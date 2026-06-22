import Foundation
import SearchModels
import ServicesModels
import SharedConstants

// MARK: - Documentation Search Service

/// Service for searching Apple documentation, Swift Evolution, and other
/// indexed sources. Internally holds an `any Search.Database` so the
/// service can be driven by the production `Search.Index` actor or by a
/// test stub conforming to `Search.Database`. The composition root
/// (CLI / MCP / TUI) constructs the database and passes it in via
/// `init(database:)`; this file no longer takes a behavioural dependency
/// on the SearchAPI target.
extension Services {
    public actor DocsSearchService: Services.SearchService {
        private let index: any Search.Database
        /// #1286 — per-source docs index map (source-id → that source's
        /// read-only database). The source-keyed operations (`search`,
        /// `listDocuments`, `listChildren`) route to the matching per-source
        /// DB; without this they all hit the single apple-docs primary
        /// `index`, so a specific-source MCP call (`search --source hig`,
        /// `list_documents source=swift-evolution`) returned empty on a
        /// per-source-DB bundle (#1036). Falls back to `index` when a source
        /// is absent from the map (legacy single-DB wiring / tests).
        private let docsIndexBySource: [String: any Search.Database]

        /// Initialize with any `Search.Database` conformer. Production:
        /// pass a `Search.Index` from the SearchSQLite target; it conforms to
        /// `Search.Database`, so the actor flows through this protocol-
        /// typed init unchanged. Tests pass a mock. `docsIndexBySource`
        /// (#1286) routes source-scoped operations to per-source DBs; empty
        /// → previous single-DB behaviour.
        public init(database: any Search.Database, docsIndexBySource: [String: any Search.Database] = [:]) {
            index = database
            self.docsIndexBySource = docsIndexBySource
        }

        /// Route a source-scoped operation to that source's per-source DB,
        /// falling back to the primary `index` when the source is nil or not
        /// in the map.
        private func docsIndex(for source: String?) -> any Search.Database {
            guard let source, let routed = docsIndexBySource[source] else { return index }
            return routed
        }

        // MARK: - Services.SearchService Protocol

        public func search(_ query: Services.SearchQuery) async throws -> [Search.Result] {
            // Platform version filtering is now done at SQL level for better performance
            try await docsIndex(for: query.source).search(
                query: query.text,
                source: query.source,
                framework: query.framework,
                language: query.language,
                limit: query.limit,
                includeArchive: query.includeArchive,
                minIOS: query.minimumiOS,
                minMacOS: query.minimumMacOS,
                minTvOS: query.minimumTvOS,
                minWatchOS: query.minimumWatchOS,
                minVisionOS: query.minimumVisionOS,
                minSwift: query.minimumSwift
            )
        }

        public func read(uri: String, format: Search.DocumentFormat) async throws -> String? {
            try await index.getDocumentContent(uri: uri, format: format)
        }

        public func listFrameworks() async throws -> [String: Int] {
            try await index.listFrameworks()
        }

        public func listDocuments(
            source: String,
            framework: String,
            offset: Int,
            limit: Int
        ) async throws -> Search.DocumentListPage {
            guard let listing = docsIndex(for: source) as? any Search.DocumentListing else {
                throw Search.Error.searchFailed("Document listing is not supported by this search database")
            }
            return try await listing.listDocuments(
                source: source,
                framework: framework,
                offset: offset,
                limit: limit
            )
        }

        public func documentCount() async throws -> Int {
            try await index.documentCount()
        }

        public func disconnect() async {
            await index.disconnect()
        }

        // MARK: - Convenience Methods

        /// Search with a simple text query using defaults
        public func search(text: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> [Search.Result] {
            try await search(Services.SearchQuery(text: text, limit: limit))
        }

        /// Search within a specific framework
        public func search(text: String, framework: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> [Search.Result] {
            try await search(Services.SearchQuery(text: text, framework: framework, limit: limit))
        }

        /// Search within a specific source (apple-docs, swift-evolution, etc.)
        public func search(text: String, source: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> [Search.Result] {
            try await search(Services.SearchQuery(text: text, source: source, limit: limit))
        }
    }
}
