import Foundation
import Search
import Shared

// MARK: - Documentation Search Service

/// Service for searching Apple documentation, Swift Evolution, and other indexed sources.
/// Wraps Search.Index with a clean interface for both CLI and MCP consumers.
public actor DocsSearchService: SearchService {
    private let index: Search.Index

    /// Initialize with an existing search index
    public init(index: Search.Index) {
        self.index = index
    }

    /// Initialize with a database path, creating a new index connection
    public init(dbPath: URL) async throws {
        index = try await Search.Index(dbPath: dbPath)
    }

    // MARK: - SearchService Protocol

    public func search(_ query: SearchQuery) async throws -> [Search.Result] {
        try await index.search(
            query: query.text,
            source: query.source,
            framework: query.framework,
            language: query.language,
            limit: query.limit,
            includeArchive: query.includeArchive
        )
    }

    public func read(uri: String, format: Search.Index.DocumentFormat) async throws -> String? {
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
        try await search(SearchQuery(text: text, limit: limit))
    }

    /// Search within a specific framework
    public func search(text: String, framework: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> [Search.Result] {
        try await search(SearchQuery(text: text, framework: framework, limit: limit))
    }

    /// Search within a specific source (apple-docs, swift-evolution, etc.)
    public func search(text: String, source: String, limit: Int = Shared.Constants.Limit.defaultSearchLimit) async throws -> [Search.Result] {
        try await search(SearchQuery(text: text, source: source, limit: limit))
    }
}
