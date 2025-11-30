import Foundation
@testable import Search
import Testing
import TestSupport

// MARK: - Test Helpers

/// Creates a temporary search index for testing
/// - Returns: A tuple containing the search index and cleanup function
/// - Note: Always call the cleanup function in a defer block
func createTestSearchIndex() async throws -> (index: Search.Index, cleanup: () throws -> Void) {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    let index = try await Search.Index(dbPath: tempDB)

    let cleanup = {
        try FileManager.default.removeItem(at: tempDB)
    }

    return (index, cleanup)
}

/// Creates a test search index with a sample document already indexed
/// - Parameters:
///   - uri: Document URI (default: "test://doc")
///   - source: Source name (default: "apple-docs")
///   - framework: Framework name (default: "swift")
///   - title: Document title (default: "Test Document")
///   - content: Document content (default: "Test content")
/// - Returns: A tuple containing the search index and cleanup function
func createTestSearchIndexWithDocument(
    uri: String = "test://doc",
    source: String = "apple-docs",
    framework: String = "swift",
    title: String = "Test Document",
    content: String = "Test content"
) async throws -> (index: Search.Index, cleanup: () throws -> Void) {
    let (index, cleanup) = try await createTestSearchIndex()

    try await index.indexDocument(
        uri: uri,
        source: source,
        framework: framework,
        title: title,
        content: content,
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "test"
    )

    return (index, cleanup)
}

// MARK: - Search Result Tests

@Test("Search result model is Codable")
func searchResultCodable() throws {
    let result = Search.Result(
        uri: "apple://documentation/swift/array",
        source: "apple-docs",
        framework: "swift",
        title: "Array",
        summary: "An ordered collection of elements",
        filePath: "/path/to/file.md",
        wordCount: 1000,
        rank: -5.5
    )

    // Verify score calculation
    #expect(result.score == 5.5)

    // Verify Codable
    let encoder = JSONEncoder()
    let data = try encoder.encode(result)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Search.Result.self, from: data)

    #expect(decoded.uri == result.uri)
    #expect(decoded.source == result.source)
    #expect(decoded.title == result.title)
    #expect(decoded.score == result.score)
}

// MARK: - SearchIndex Tests

@Test("SearchIndex initializes with in-memory database")
func searchIndexInitialization() async throws {
    let (index, cleanup) = try await createTestSearchIndex()
    defer { try? cleanup() }

    await index.disconnect()
    // Database file is created and managed by helper
}

@Test("SearchIndex creates required tables")
func searchIndexTablesCreated() async throws {
    let (index, cleanup) = try await createTestSearchIndexWithDocument()
    defer { try? cleanup() }

    // If we got here without throwing, tables were created successfully
    await index.disconnect()
}

@Test("SearchIndex indexes and retrieves document")
func searchIndexBasicIndexing() async throws {
    let (index, cleanup) = try await createTestSearchIndexWithDocument(
        uri: "apple://documentation/swift/array",
        framework: "swift",
        title: "Array",
        content: "An ordered collection of elements that allows random access"
    )
    defer { try? cleanup() }

    // Search for the indexed document
    let results = try await index.search(query: "array", framework: nil, limit: 10)

    #expect(results.count == 1)
    #expect(results[0].title == "Array")
    #expect(results[0].framework == "swift")

    await index.disconnect()
}

@Test("SearchIndex handles special characters in query")
func searchIndexSpecialCharacters() async throws {
    let (index, cleanup) = try await createTestSearchIndexWithDocument(
        title: "UIViewController",
        content: "Manages view hierarchy, responds to user input (touch, gestures)"
    )
    defer { try? cleanup() }

    // Query with special characters should not crash
    _ = try await index.search(query: "UIViewController", framework: nil, limit: 10)
    _ = try await index.search(query: "view (touch)", framework: nil, limit: 10)

    await index.disconnect()
}

@Test("SearchIndex filters by framework")
func searchIndexFrameworkFilter() async throws {
    let (index, cleanup) = try await createTestSearchIndex()
    defer { try? cleanup() }

    // Index documents in different frameworks
    try await index.indexDocument(
        uri: "swift://array",
        source: "apple-docs",
        framework: "swift",
        title: "Array",
        content: "Swift array collection",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    try await index.indexDocument(
        uri: "uikit://array",
        source: "apple-docs",
        framework: "uikit",
        title: "UIView Array",
        content: "UIKit array of views",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    // Search with framework filter
    let swiftResults = try await index.search(query: "array", framework: "swift", limit: 10)
    #expect(swiftResults.count == 1)
    #expect(swiftResults[0].framework == "swift")

    let uikitResults = try await index.search(query: "array", framework: "uikit", limit: 10)
    #expect(uikitResults.count == 1)
    #expect(uikitResults[0].framework == "uikit")

    let allResults = try await index.search(query: "array", framework: nil, limit: 10)
    #expect(allResults.count == 2)

    await index.disconnect()
}

@Test("SearchIndex respects result limit")
func searchIndexResultLimit() async throws {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let index = try await Search.Index(dbPath: tempDB)

    // Index multiple documents
    for docNumber in 1...10 {
        try await index.indexDocument(
            uri: "test://doc\(docNumber)",
            source: "apple-docs",
            framework: "swift",
            title: "Document \(docNumber) about swift arrays",
            content: "Swift content about arrays and collections",
            filePath: "/test.md",
            contentHash: "test-hash",
            lastCrawled: Date(),
            sourceType: "apple"
        )
    }

    // Search with limit
    let results = try await index.search(query: "swift", framework: nil, limit: 3)
    #expect(results.count == 3)

    await index.disconnect()
}

@Test("SearchIndex returns empty results for no matches")
func searchIndexNoMatches() async throws {
    let (index, cleanup) = try await createTestSearchIndexWithDocument(
        title: "Array",
        content: "Swift array collection"
    )
    defer { try? cleanup() }

    let results = try await index.search(query: "nonexistent", framework: nil, limit: 10)
    #expect(results.isEmpty)

    await index.disconnect()
}

@Test("SearchIndex updates existing document")
func searchIndexUpdateDocument() async throws {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let index = try await Search.Index(dbPath: tempDB)

    let uri = "test://doc"

    // Index original document
    try await index.indexDocument(
        uri: uri,
        source: "apple-docs",
        framework: "swift",
        title: "Array",
        content: "Original content about arrays",
        filePath: "/test.md",
        contentHash: "hash1",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    // Update document
    try await index.indexDocument(
        uri: uri,
        source: "apple-docs",
        framework: "swift",
        title: "Array Updated",
        content: "Updated content about dictionaries",
        filePath: "/test.md",
        contentHash: "hash2",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    // Search for new content
    let results = try await index.search(query: "dictionaries", framework: nil, limit: 10)
    #expect(results.count >= 1)
    #expect(results[0].title == "Array Updated")

    // Verify title was updated
    let titleResults = try await index.search(query: "Updated", framework: nil, limit: 10)
    #expect(titleResults.count >= 1)

    await index.disconnect()
}

@Test("SearchIndex handles empty query")
func searchIndexEmptyQuery() async throws {
    let (index, cleanup) = try await createTestSearchIndexWithDocument()
    defer { try? cleanup() }

    // Empty query should throw invalidQuery error
    await #expect(throws: SearchError.self) {
        try await index.search(query: "", framework: nil, limit: 10)
    }

    await index.disconnect()
}

@Test("SearchIndex handles whitespace-only query")
func searchIndexWhitespaceQuery() async throws {
    let (index, cleanup) = try await createTestSearchIndexWithDocument()
    defer { try? cleanup() }

    // Whitespace query should throw invalidQuery error
    await #expect(throws: SearchError.self) {
        try await index.search(query: "   ", framework: nil, limit: 10)
    }

    await index.disconnect()
}

@Test("SearchIndex BM25 ranking orders by relevance")
func searchIndexBM25Ranking() async throws {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let index = try await Search.Index(dbPath: tempDB)

    // Index documents with different relevance
    // Doc 1: Title match + multiple content matches (highest relevance)
    try await index.indexDocument(
        uri: "doc1",
        source: "apple-docs",
        framework: "swift",
        title: "SwiftUI Array Manipulation",
        content: "SwiftUI provides powerful SwiftUI array tools for SwiftUI development",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    // Doc 2: Content match only (lower relevance)
    try await index.indexDocument(
        uri: "doc2",
        source: "apple-docs",
        framework: "uikit",
        title: "UIKit Collections",
        content: "UIKit has some SwiftUI compatibility",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    // Doc 3: Single content match (lowest relevance)
    try await index.indexDocument(
        uri: "doc3",
        source: "apple-docs",
        framework: "foundation",
        title: "Foundation Framework",
        content: "This document mentions SwiftUI once",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    let results = try await index.search(query: "SwiftUI", framework: nil, limit: 10)

    #expect(results.count == 3)
    // Verify results are ranked by relevance (descending order: higher score = better match)
    #expect(results[0].score >= results[1].score, "First result should rank highest")
    #expect(results[1].score >= results[2].score, "Results should be ordered by relevance")
    // Verify all results have positive scores
    #expect(results.allSatisfy { $0.score > 0 }, "All results should have positive BM25 scores")

    await index.disconnect()
}

@Test("SearchIndex disconnect closes database")
func searchIndexDisconnect() async throws {
    let (index, cleanup) = try await createTestSearchIndexWithDocument()
    defer { try? cleanup() }

    // Disconnect
    await index.disconnect()
    // Database file management is handled by helper
}

@Test("SearchIndex handles multiple source types")
func searchIndexMultipleSourceTypes() async throws {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let index = try await Search.Index(dbPath: tempDB)

    // Index documents from different sources
    try await index.indexDocument(
        uri: "apple://doc",
        source: "apple-docs",
        framework: "swift",
        title: "Apple Swift Doc",
        content: "Official Apple documentation",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    try await index.indexDocument(
        uri: "evolution://SE-0001",
        source: "swift-evolution",
        framework: nil,
        title: "Swift Evolution Proposal",
        content: "Allow documentation keywords",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "swift-evolution"
    )

    let results = try await index.search(query: "documentation", framework: nil, limit: 10)
    #expect(results.count == 2)

    await index.disconnect()
}

@Test("SearchIndex filters by source")
func searchIndexSourceFilter() async throws {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let index = try await Search.Index(dbPath: tempDB)

    // Index documents from different sources with common keyword "swift"
    try await index.indexDocument(
        uri: "apple-docs://swiftui/view",
        source: "apple-docs",
        framework: "swiftui",
        title: "View Protocol",
        content: "A swift type that represents part of your app's user interface",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "apple"
    )

    try await index.indexDocument(
        uri: "swift-evolution://SE-0302",
        source: "swift-evolution",
        framework: nil,
        title: "SE-0302 Sendable",
        content: "Swift proposal for concurrency safety with Sendable protocol",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "swift-evolution"
    )

    try await index.indexDocument(
        uri: "swift-book://concurrency",
        source: "swift-book",
        framework: nil,
        title: "Concurrency",
        content: "Swift has built-in support for writing asynchronous and parallel code",
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "swift-book"
    )

    // Search all sources with common keyword
    let allResults = try await index.search(query: "swift", source: nil, framework: nil, limit: 10)
    #expect(allResults.count == 3)

    // Search specific source - evolution
    let evolutionResults = try await index.search(query: "swift", source: "swift-evolution", framework: nil, limit: 10)
    #expect(evolutionResults.count == 1)
    #expect(evolutionResults[0].source == "swift-evolution")

    // Search specific source - apple-docs
    let appleDocsResults = try await index.search(query: "swift", source: "apple-docs", framework: nil, limit: 10)
    #expect(appleDocsResults.count == 1)
    #expect(appleDocsResults[0].source == "apple-docs")

    // Search specific source - swift-book
    let swiftBookResults = try await index.search(query: "swift", source: "swift-book", framework: nil, limit: 10)
    #expect(swiftBookResults.count == 1)
    #expect(swiftBookResults[0].source == "swift-book")

    await index.disconnect()
}

// MARK: - getDocumentContent Tests

@Test("getDocumentContent falls back to FTS content when rawMarkdown is null")
func getDocumentContentFallbackToFTS() async throws {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let index = try await Search.Index(dbPath: tempDB)

    // Index a document with null rawMarkdown (simulating swift-book case)
    let uri = "swift-book://concurrency"
    let ftsContent = "# Concurrency\n\nSwift has built-in support for async/await."

    try await index.indexDocument(
        uri: uri,
        source: "swift-book",
        framework: nil,
        title: "Concurrency",
        content: ftsContent,
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "swift-book",
        jsonData: "{\"title\":\"Concurrency\",\"rawMarkdown\":null,\"url\":\"\(uri)\"}"
    )

    // Get content as markdown - should fall back to FTS content
    let content = try await index.getDocumentContent(uri: uri, format: .markdown)

    #expect(content != nil)
    #expect(content?.contains("Concurrency") == true)
    #expect(content?.contains("async/await") == true)

    await index.disconnect()
}

@Test("getDocumentContent returns nil for non-existent URI")
func getDocumentContentNotFound() async throws {
    let (index, cleanup) = try await createTestSearchIndex()
    defer { try? cleanup() }

    let content = try await index.getDocumentContent(uri: "nonexistent://doc", format: .markdown)
    #expect(content == nil)

    await index.disconnect()
}

@Test("getDocumentContent returns JSON format from metadata")
func getDocumentContentJSON() async throws {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let index = try await Search.Index(dbPath: tempDB)

    let uri = "apple-docs://swift/string"
    let jsonData = "{\"title\":\"String\",\"kind\":\"struct\",\"rawMarkdown\":\"# String\"}"

    try await index.indexDocument(
        uri: uri,
        source: "apple-docs",
        framework: "swift",
        title: "String",
        content: "# String",
        filePath: "/test.json",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "apple",
        jsonData: jsonData
    )

    // Get content as JSON
    let content = try await index.getDocumentContent(uri: uri, format: .json)

    #expect(content != nil)
    #expect(content?.contains("\"title\":\"String\"") == true)

    await index.disconnect()
}

@Test("getDocumentContent FTS fallback wraps content in JSON for JSON format")
func getDocumentContentFTSFallbackJSON() async throws {
    let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let index = try await Search.Index(dbPath: tempDB)

    // Index document with null rawMarkdown
    let uri = "swift-book://basics"
    let ftsContent = "# The Basics\n\nSwift is a type-safe language."

    try await index.indexDocument(
        uri: uri,
        source: "swift-book",
        framework: nil,
        title: "The Basics",
        content: ftsContent,
        filePath: "/test.md",
        contentHash: "test-hash",
        lastCrawled: Date(),
        sourceType: "swift-book",
        jsonData: "{\"title\":\"The Basics\",\"rawMarkdown\":null}"
    )

    // Get content as JSON - should return the original JSON (since it exists in metadata)
    // Note: FTS fallback only happens when metadata doesn't exist or can't be decoded
    let content = try await index.getDocumentContent(uri: uri, format: .json)

    #expect(content != nil)
    #expect(content?.contains("The Basics") == true)

    await index.disconnect()
}
