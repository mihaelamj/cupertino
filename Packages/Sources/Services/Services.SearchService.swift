import Foundation
import SearchModels
import ServicesModels
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

// `Services.SearchQuery` and `Services.SearchFilters` value types
// lifted to the `ServicesModels` target so consumers
// (`SearchToolProvider`, future CLI / MCP surfaces) can construct
// them without importing the full `Services` target.
