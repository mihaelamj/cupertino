import Foundation
import SearchModels
import SharedConstants
import SharedCore

// MARK: - Search Service Protocol

/// Protocol for search operations across different documentation sources.
/// Provides a unified interface for CLI commands and MCP tool providers.
extension Services {
    public protocol SearchService: Actor {
        /// Search for documents matching the query
        func search(_ query: SearchQuery) async throws -> [Search.Result]

        /// Get document content by URI
        func read(uri: String, format: Search.DocumentFormat) async throws -> String?

        /// List all available frameworks with document counts
        func listFrameworks() async throws -> [String: Int]

        /// Get total document count
        func documentCount() async throws -> Int

        /// Disconnect from the underlying database
        func disconnect() async
    }
}

// MARK: - Search Query

/// Common search query parameters for all search operations
extension Services {
    public struct SearchQuery: Sendable {
        public let text: String
        public let source: String?
        public let framework: String?
        public let language: String?
        public let limit: Int
        public let includeArchive: Bool
        public let minimumiOS: String?
        public let minimumMacOS: String?
        public let minimumTvOS: String?
        public let minimumWatchOS: String?
        public let minimumVisionOS: String?

        public init(
            text: String,
            source: String? = nil,
            framework: String? = nil,
            language: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit,
            includeArchive: Bool = false,
            minimumiOS: String? = nil,
            minimumMacOS: String? = nil,
            minimumTvOS: String? = nil,
            minimumWatchOS: String? = nil,
            minimumVisionOS: String? = nil
        ) {
            self.text = text
            self.source = source
            self.framework = framework
            self.language = language
            self.limit = min(limit, Shared.Constants.Limit.maxSearchLimit)
            self.includeArchive = includeArchive
            self.minimumiOS = minimumiOS
            self.minimumMacOS = minimumMacOS
            self.minimumTvOS = minimumTvOS
            self.minimumWatchOS = minimumWatchOS
            self.minimumVisionOS = minimumVisionOS
        }
    }
}

// MARK: - Search Filters

/// Active filters for formatting search results
extension Services {
    public struct SearchFilters: Sendable {
        public let source: String?
        public let framework: String?
        public let language: String?
        public let minimumiOS: String?
        public let minimumMacOS: String?
        public let minimumTvOS: String?
        public let minimumWatchOS: String?
        public let minimumVisionOS: String?

        public init(
            source: String? = nil,
            framework: String? = nil,
            language: String? = nil,
            minimumiOS: String? = nil,
            minimumMacOS: String? = nil,
            minimumTvOS: String? = nil,
            minimumWatchOS: String? = nil,
            minimumVisionOS: String? = nil
        ) {
            self.source = source
            self.framework = framework
            self.language = language
            self.minimumiOS = minimumiOS
            self.minimumMacOS = minimumMacOS
            self.minimumTvOS = minimumTvOS
            self.minimumWatchOS = minimumWatchOS
            self.minimumVisionOS = minimumVisionOS
        }

        /// Check if any filters are active
        public var hasActiveFilters: Bool {
            source != nil || framework != nil || language != nil ||
                minimumiOS != nil || minimumMacOS != nil || minimumTvOS != nil ||
                minimumWatchOS != nil || minimumVisionOS != nil
        }
    }
}
