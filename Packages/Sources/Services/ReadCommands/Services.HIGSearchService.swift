import Foundation
import Search
import SharedConstants
import SharedCore
import SearchModels

// MARK: - HIG Search Query

/// Specialized query for Human Interface Guidelines searches
extension Services {
    public struct HIGQuery: Sendable {
        public let text: String
        public let platform: String? // iOS, macOS, watchOS, visionOS, tvOS
        public let category: String? // foundations, patterns, components, technologies, inputs
        public let limit: Int

        public init(
            text: String,
            platform: String? = nil,
            category: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) {
            self.text = text
            self.platform = platform
            self.category = category
            self.limit = min(limit, Shared.Constants.Limit.maxSearchLimit)
        }
    }
}

// MARK: - HIG Search Service

/// Service for searching Human Interface Guidelines.
/// Delegates to Services.DocsSearchService with HIG-specific source filtering.
extension Services {
    public actor HIGSearchService {
        private let docsService: Services.DocsSearchService

        /// Initialize with an existing docs service
        public init(docsService: Services.DocsSearchService) {
            self.docsService = docsService
        }

        /// Initialize with a search index.
        public init(index: Search.Index) {
            docsService = Services.DocsSearchService(index: index)
        }

        /// Initialize with any `Search.Database` conformer.
        public init(database: any Search.Database) {
            docsService = Services.DocsSearchService(database: database)
        }

        /// Initialize with a database path.
        public init(dbPath: URL) async throws {
            let index = try await Search.Index(dbPath: dbPath)
            docsService = Services.DocsSearchService(index: index)
        }

        // MARK: - Search Methods

        /// Search HIG with specialized query
        public func search(_ query: Services.HIGQuery) async throws -> [Search.Result] {
            // Build effective query with platform/category filters
            var effectiveText = query.text
            if let platform = query.platform {
                effectiveText += " \(platform)"
            }
            if let category = query.category {
                effectiveText += " \(category)"
            }

            let searchQuery = Services.SearchQuery(
                text: effectiveText,
                source: Shared.Constants.SourcePrefix.hig,
                limit: query.limit,
                includeArchive: false
            )

            return try await docsService.search(searchQuery)
        }

        /// Simple text search in HIG
        public func search(text: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> [Search.Result] {
            try await search(Services.HIGQuery(text: text, limit: limit))
        }

        /// Search HIG for a specific platform
        public func search(text: String, platform: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> [Search.Result] {
            try await search(Services.HIGQuery(text: text, platform: platform, limit: limit))
        }

        /// Search HIG for a specific category
        public func search(text: String, category: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> [Search.Result] {
            try await search(Services.HIGQuery(text: text, category: category, limit: limit))
        }

        // MARK: - Document Access

        /// Read a HIG document by URI
        public func read(uri: String, format: Search.DocumentFormat = .json) async throws -> String? {
            try await docsService.read(uri: uri, format: format)
        }

        /// Disconnect from the underlying database
        public func disconnect() async {
            await docsService.disconnect()
        }
    }
}
