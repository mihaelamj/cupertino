import AppKit
@testable import CLI
@testable import Core
import Foundation
@testable import Search
@testable import Shared
import Testing
import TestSupport

// MARK: - Index Command Tests

/// Tests for the `cupertino index` command
/// Verifies search index building, framework filtering, and empty directory handling

@Suite("Index Command Tests")
struct IndexCommandTests {
    @Test("Build search index from crawled docs", .tags(.integration))
    @MainActor
    func buildSearchIndex() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-index-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Build search index")

        // First, crawl a page to have data
        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(forceRecrawl: true),
            output: Shared.OutputConfiguration(format: .markdown)
        )

        let crawler = await Core.Crawler(configuration: config)
        _ = try await crawler.crawl()

        // Build search index
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        let metadata = try CrawlMetadata.load(from: tempDir.appendingPathComponent("metadata.json"))
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: metadata,
            docsDirectory: tempDir,
            evolutionDirectory: nil
        )

        try await builder.buildIndex()

        // Verify search.db was created
        #expect(FileManager.default.fileExists(atPath: searchDbPath.path), "Search database should exist")

        // Verify we can search
        let results = try await searchIndex.search(query: "swift", limit: 10)
        #expect(!results.isEmpty, "Search should return results")

        print("   ✅ Found \(results.count) search results")
        if let firstResult = results.first {
            print("   ✅ First result: \(firstResult.title)")
        }

        print("   ✅ Index build test passed!")
    }

    @Test("Search index with framework filter", .tags(.integration))
    @MainActor
    func searchWithFrameworkFilter() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-search-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Search with framework filter")

        // Crawl and index
        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(forceRecrawl: true),
            output: Shared.OutputConfiguration(format: .markdown)
        )

        let crawler = await Core.Crawler(configuration: config)
        _ = try await crawler.crawl()

        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        let metadata = try CrawlMetadata.load(from: tempDir.appendingPathComponent("metadata.json"))
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: metadata,
            docsDirectory: tempDir,
            evolutionDirectory: nil
        )
        try await builder.buildIndex()

        // Search with framework filter
        let allResults = try await searchIndex.search(query: "array", limit: 10)
        let swiftResults = try await searchIndex.search(query: "array", framework: "swift", limit: 10)

        #expect(!allResults.isEmpty, "General search should return results")

        if !swiftResults.isEmpty {
            for result in swiftResults {
                #expect(result.framework == "swift", "Filtered results should match framework")
            }
            print("   ✅ Framework filter working correctly")
        }

        print("   ✅ Search filter test passed!")
    }

    @Test("Index handles empty directory gracefully")
    func indexEmptyDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-empty-index-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        print("🧪 Test: Index empty directory")

        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        // Create empty metadata
        let emptyMetadata = CrawlMetadata()
        let metadataFile = tempDir.appendingPathComponent("metadata.json")
        try emptyMetadata.save(to: metadataFile)

        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: emptyMetadata,
            docsDirectory: tempDir,
            evolutionDirectory: nil
        )

        // Should not throw, just index 0 documents
        try await builder.buildIndex()

        let results = try await searchIndex.search(query: "anything", limit: 10)
        #expect(results.isEmpty, "Empty index should return no results")

        print("   ✅ Empty directory test passed!")
    }
}
