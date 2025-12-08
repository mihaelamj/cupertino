import Foundation
import Search
import Shared

// MARK: - Search Service Protocol

/// Protocol for search operations across different documentation sources.
/// Provides a unified interface for CLI commands and MCP tool providers.
public protocol SearchService: Actor {
    /// Search for documents matching the query
    func search(_ query: SearchQuery) async throws -> [Search.Result]

    /// Get document content by URI
    func read(uri: String, format: Search.Index.DocumentFormat) async throws -> String?

    /// List all available frameworks with document counts
    func listFrameworks() async throws -> [String: Int]

    /// Get total document count
    func documentCount() async throws -> Int

    /// Disconnect from the underlying database
    func disconnect() async
}

// MARK: - Search Query

/// Common search query parameters for all search operations
public struct SearchQuery: Sendable {
    public let text: String
    public let source: String?
    public let framework: String?
    public let language: String?
    public let limit: Int
    public let includeArchive: Bool

    public init(
        text: String,
        source: String? = nil,
        framework: String? = nil,
        language: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit,
        includeArchive: Bool = false
    ) {
        self.text = text
        self.source = source
        self.framework = framework
        self.language = language
        self.limit = min(limit, Shared.Constants.Limit.maxSearchLimit)
        self.includeArchive = includeArchive
    }
}

// MARK: - Search Filters

/// Active filters for formatting search results
public struct SearchFilters: Sendable {
    public let source: String?
    public let framework: String?
    public let language: String?

    public init(source: String? = nil, framework: String? = nil, language: String? = nil) {
        self.source = source
        self.framework = framework
        self.language = language
    }

    /// Check if any filters are active
    public var hasActiveFilters: Bool {
        source != nil || framework != nil || language != nil
    }
}
