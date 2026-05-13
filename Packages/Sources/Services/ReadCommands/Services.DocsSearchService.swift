import Foundation
import Search
import SearchModels
import SharedConstants
import SharedCore

// MARK: - Documentation Search Service

/// Service for searching Apple documentation, Swift Evolution, and other
/// indexed sources. Internally holds an `any Search.Database` so the
/// service can be driven by the production `Search.Index` actor or by a
/// test stub conforming to `Search.Database`.
extension Services {
    public actor DocsSearchService: Services.SearchService {
        private let index: any Search.Database

        /// Initialize with an existing search index. Callers passing a
        /// concrete `Search.Index` continue to compile unchanged because
        /// `Search.Index` conforms to `Search.Database`.
        public init(index: Search.Index) {
            self.index = index
        }

        /// Initialize with any `Search.Database` conformer. Tests pass a
        /// mock; CLI / MCP composition roots can opt into this overload
        /// to avoid threading the concrete actor type through their wiring.
        public init(database: any Search.Database) {
            self.index = database
        }

        /// Initialize with a database path, creating a new index connection.
        public init(dbPath: URL) async throws {
            index = try await Search.Index(dbPath: dbPath)
        }

        // MARK: - Services.SearchService Protocol

        public func search(_ query: Services.SearchQuery) async throws -> [Search.Result] {
            // Platform version filtering is now done at SQL level for better performance
            try await index.search(
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
                minVisionOS: query.minimumVisionOS
            )
        }

        public func read(uri: String, format: Search.DocumentFormat) async throws -> String? {
            try await index.getDocumentContent(uri: uri, format: format)
        }

        public func listFrameworks() async throws -> [String: Int] {
            try await index.listFrameworks()
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
