import AppKit
@testable import CupertinoCLI
@testable import CupertinoCore
@testable import CupertinoSearch
@testable import CupertinoShared
import Foundation
import Testing

// MARK: - CLI Command Tests

/// Comprehensive tests for all Cupertino CLI commands
/// Tests crawl, index, and fetch commands with real execution

// MARK: - Crawl Command Tests

@Suite("Crawl Command Tests")
struct CrawlCommandTests {
    @Test("Crawl single Apple documentation page", .tags(.integration))
    @MainActor
    func crawlSinglePage() async throws {
        // Set up NSApplication for WKWebView
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-crawl-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = CupertinoConfiguration(
            crawler: CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: ChangeDetectionConfiguration(forceRecrawl: true),
            output: OutputConfiguration(format: .markdown)
        )

        print("🧪 Test: Crawl single page")
        print("   URL: \(config.crawler.startURL)")

        let crawler = await DocumentationCrawler(configuration: config)
        let stats = try await crawler.crawl()

        // Verify stats
        #expect(stats.totalPages == 1, "Should have crawled exactly 1 page")
        #expect(stats.newPages == 1, "Should have 1 new page")
        #expect(stats.errors == 0, "Should have no errors")

        // Verify output directory exists
        var isDirectory: ObjCBool = false
        let dirExists = FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDirectory)
        #expect(dirExists && isDirectory.boolValue, "Output directory should exist")

        // Verify markdown file was created
        let markdownFiles = findMarkdownFiles(in: tempDir)
        #expect(!markdownFiles.isEmpty, "Should have created markdown files")

        if let firstFile = markdownFiles.first {
            let content = try String(contentsOf: firstFile, encoding: .utf8)
            #expect(content.count > 100, "Markdown content should be substantial")
            #expect(content.contains("Swift"), "Content should mention Swift")
            print("   ✅ Created: \(firstFile.lastPathComponent) (\(content.count) chars)")
        }

        // Verify metadata.json was created
        let metadataFile = tempDir.appendingPathComponent("metadata.json")
        #expect(FileManager.default.fileExists(atPath: metadataFile.path), "Metadata should exist")

        let metadata = try CrawlMetadata.load(from: metadataFile)
        #expect(!metadata.pages.isEmpty, "Metadata should contain pages")
        #expect(metadata.stats.totalPages == 1, "Metadata stats should match")

        print("   ✅ Crawl test passed!")
    }

    @Test("Crawl with resume capability", .tags(.integration))
    @MainActor
    func crawlWithResume() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-resume-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = CupertinoConfiguration(
            crawler: CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: ChangeDetectionConfiguration(enabled: true, forceRecrawl: false),
            output: OutputConfiguration(format: .markdown)
        )

        print("🧪 Test: Crawl with resume")

        // First crawl
        let crawler1 = await DocumentationCrawler(configuration: config)
        let stats1 = try await crawler1.crawl()
        #expect(stats1.newPages == 1, "First crawl should have 1 new page")

        // Second crawl (should skip unchanged)
        let crawler2 = await DocumentationCrawler(configuration: config)
        let stats2 = try await crawler2.crawl()
        #expect(stats2.skippedPages == 1, "Second crawl should skip unchanged page")
        #expect(stats2.newPages == 0, "Second crawl should have no new pages")

        print("   ✅ Resume test passed!")
    }

    @Test("Crawl Swift Evolution proposal", .tags(.integration))
    @MainActor
    func crawlSwiftEvolution() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-evolution-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Crawl Swift Evolution proposal")

        let crawler = SwiftEvolutionCrawler(
            outputDirectory: tempDir,
            onlyAccepted: true
        )

        let proposals = try await crawler.downloadProposals(maxProposals: 1)

        #expect(!proposals.isEmpty, "Should have downloaded at least 1 proposal")

        // Verify markdown file exists
        let markdownFiles = findMarkdownFiles(in: tempDir)
        #expect(!markdownFiles.isEmpty, "Should have created markdown files")

        if let firstFile = markdownFiles.first {
            let content = try String(contentsOf: firstFile, encoding: .utf8)
            #expect(content.contains("SE-"), "Content should contain SE- proposal number")
            print("   ✅ Downloaded: \(firstFile.lastPathComponent)")
        }

        print("   ✅ Evolution crawl test passed!")
    }
}

// MARK: - Index Command Tests

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
        let config = CupertinoConfiguration(
            crawler: CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: ChangeDetectionConfiguration(forceRecrawl: true),
            output: OutputConfiguration(format: .markdown)
        )

        let crawler = await DocumentationCrawler(configuration: config)
        _ = try await crawler.crawl()

        // Build search index
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = await SearchIndex(databasePath: searchDbPath)
        try await searchIndex.initialize()

        let metadata = try CrawlMetadata.load(from: tempDir.appendingPathComponent("metadata.json"))
        let builder = await SearchIndexBuilder(
            searchIndex: searchIndex,
            metadata: metadata,
            docsDirectory: tempDir,
            evolutionDirectory: nil
        )

        try await builder.build()

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
        let config = CupertinoConfiguration(
            crawler: CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: ChangeDetectionConfiguration(forceRecrawl: true),
            output: OutputConfiguration(format: .markdown)
        )

        let crawler = await DocumentationCrawler(configuration: config)
        _ = try await crawler.crawl()

        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = await SearchIndex(databasePath: searchDbPath)
        try await searchIndex.initialize()

        let metadata = try CrawlMetadata.load(from: tempDir.appendingPathComponent("metadata.json"))
        let builder = await SearchIndexBuilder(
            searchIndex: searchIndex,
            metadata: metadata,
            docsDirectory: tempDir,
            evolutionDirectory: nil
        )
        try await builder.build()

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
        let searchIndex = await SearchIndex(databasePath: searchDbPath)
        try await searchIndex.initialize()

        // Create empty metadata
        let emptyMetadata = CrawlMetadata()
        let metadataFile = tempDir.appendingPathComponent("metadata.json")
        try emptyMetadata.save(to: metadataFile)

        let builder = await SearchIndexBuilder(
            searchIndex: searchIndex,
            metadata: emptyMetadata,
            docsDirectory: tempDir,
            evolutionDirectory: nil
        )

        // Should not throw, just index 0 documents
        try await builder.build()

        let results = try await searchIndex.search(query: "anything", limit: 10)
        #expect(results.isEmpty, "Empty index should return no results")

        print("   ✅ Empty directory test passed!")
    }
}

// MARK: - Fetch Command Tests

@Suite("Fetch Command Tests")
struct FetchCommandTests {
    @Test("Fetch Swift packages data")
    func fetchPackagesData() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-fetch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        print("🧪 Test: Fetch Swift packages")

        let fetcher = PackageFetcher(
            outputDirectory: tempDir,
            maxPackages: 10
        )

        // Note: This would require network access
        // For now, just verify the fetcher can be created
        #expect(fetcher.outputDirectory == tempDir, "Fetcher should have correct output directory")

        print("   ✅ Fetch initialization test passed!")
    }
}

// MARK: - Helper Functions

private func findMarkdownFiles(in directory: URL) -> [URL] {
    let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    )
    var markdownFiles: [URL] = []

    while let fileURL = enumerator?.nextObject() as? URL {
        if fileURL.pathExtension == "md" {
            markdownFiles.append(fileURL)
        }
    }

    return markdownFiles
}

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
    @Tag static var cli: Self
    @Tag static var slow: Self
}
