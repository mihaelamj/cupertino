import AppKit
@testable import CLI
@testable import Core
import Foundation
@testable import Search
@testable import Shared
import Testing
import TestSupport

// MARK: - Save Command Tests

/// Tests for the `cupertino save` command
/// Verifies search index building, framework filtering, and empty directory handling

@Suite("Save Command Tests", .serialized)
struct SaveCommandTests {
    @Test("Build search index from crawled docs", .tags(.integration))
    @MainActor
    func buildSearchIndex() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-save-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Build search index")

        // First, fetch a page to have data
        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(forceRecrawl: true, outputDirectory: tempDir),
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

        print("   ✅ Save build test passed!")
    }

    @Test("Search index with framework filter", .tags(.integration))
    @MainActor
    func searchWithFrameworkFilter() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-search-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Search with framework filter")

        // Fetch and save
        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(forceRecrawl: true, outputDirectory: tempDir),
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

    @Test("Save handles empty directory gracefully")
    func saveEmptyDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-empty-save-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        print("🧪 Test: Save empty directory")

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

        // Should not throw, just save 0 documents
        try await builder.buildIndex()

        let results = try await searchIndex.search(query: "anything", limit: 10)
        #expect(results.isEmpty, "Empty save should return no results")

        print("   ✅ Empty directory test passed!")
    }

    @Test("Base directory auto-fills all paths")
    func baseDirAutoFillsPaths() async throws {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-basedir-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: baseDir) }

        print("🧪 Test: Base directory auto-fills paths")

        // Create directory structure
        let docsDir = baseDir.appendingPathComponent("docs")
        let evolutionDir = baseDir.appendingPathComponent("swift-evolution")
        let searchDbPath = baseDir.appendingPathComponent("search.db")

        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evolutionDir, withIntermediateDirectories: true)

        // Create minimal metadata
        let metadata = CrawlMetadata()
        let metadataFile = baseDir.appendingPathComponent("metadata.json")
        try metadata.save(to: metadataFile)

        // Verify paths derived from base directory
        #expect(
            docsDir.path == baseDir.appendingPathComponent(Shared.Constants.Directory.docs).path,
            "docs-dir should be base-dir/docs"
        )
        #expect(
            evolutionDir.path == baseDir.appendingPathComponent(Shared.Constants.Directory.swiftEvolution).path,
            "evolution-dir should be base-dir/swift-evolution"
        )
        #expect(
            metadataFile.path == baseDir.appendingPathComponent(Shared.Constants.FileName.metadata).path,
            "metadata-file should be base-dir/metadata.json"
        )
        #expect(
            searchDbPath.path == baseDir.appendingPathComponent(Shared.Constants.FileName.searchDatabase).path,
            "search-db should be base-dir/search.db"
        )

        print("   ✅ Base directory paths verified!")

        // Test that index builds successfully with base-dir structure
        let searchIndex = try await Search.Index(dbPath: searchDbPath)
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: metadata,
            docsDirectory: docsDir,
            evolutionDirectory: evolutionDir
        )

        try await builder.buildIndex()

        #expect(FileManager.default.fileExists(atPath: searchDbPath.path), "Search DB should be created")

        print("   ✅ Base directory test passed!")
    }

    // MARK: - Directory Scanning Tests (metadata.json optional)

    @Test("Build index without metadata.json using directory scanning")
    func buildIndexWithoutMetadata() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-no-metadata-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Build index without metadata.json")

        // Create directory structure: docs/swift/array.json
        let swiftDir = tempDir.appendingPathComponent("docs/swift")
        try FileManager.default.createDirectory(at: swiftDir, withIntermediateDirectories: true)

        // Create test JSON files (StructuredDocumentationPage format)
        let arrayPage = StructuredDocumentationPage(
            url: URL(string: "https://developer.apple.com/documentation/swift/array")!,
            title: "Array",
            kind: .struct,
            source: .appleWebKit,
            abstract: "An ordered collection of elements.",
            rawMarkdown: "# Array\n\nAn ordered collection of elements."
        )
        let arrayDoc = swiftDir.appendingPathComponent("array.json")
        try JSONCoding.encode(arrayPage, to: arrayDoc)

        let dictPage = StructuredDocumentationPage(
            url: URL(string: "https://developer.apple.com/documentation/swift/dictionary")!,
            title: "Dictionary",
            kind: .struct,
            source: .appleWebKit,
            abstract: "A collection of key-value pairs.",
            rawMarkdown: "# Dictionary\n\nA collection of key-value pairs."
        )
        let dictDoc = swiftDir.appendingPathComponent("dictionary.json")
        try JSONCoding.encode(dictPage, to: dictDoc)

        // Create swiftui directory
        let swiftuiDir = tempDir.appendingPathComponent("docs/swiftui")
        try FileManager.default.createDirectory(at: swiftuiDir, withIntermediateDirectories: true)

        let viewPage = StructuredDocumentationPage(
            url: URL(string: "https://developer.apple.com/documentation/swiftui/view")!,
            title: "View",
            kind: .protocol,
            source: .appleWebKit,
            abstract: "A piece of user interface.",
            rawMarkdown: "# View\n\nA piece of user interface."
        )
        let viewDoc = swiftuiDir.appendingPathComponent("view.json")
        try JSONCoding.encode(viewPage, to: viewDoc)

        // Build index WITHOUT metadata.json
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: nil, // No metadata!
            docsDirectory: tempDir.appendingPathComponent("docs"),
            evolutionDirectory: nil
        )

        try await builder.buildIndex()

        // Verify documents were indexed
        let swiftResults = try await searchIndex.search(query: "collection", framework: "swift", limit: 10)
        #expect(!swiftResults.isEmpty, "Should find swift documents")
        #expect(swiftResults.contains(where: { $0.title.contains("Array") }), "Should index Array")

        let swiftuiResults = try await searchIndex.search(query: "interface", framework: "swiftui", limit: 10)
        #expect(!swiftuiResults.isEmpty, "Should find swiftui documents")

        // Verify framework extraction from folder path
        let allResults = try await searchIndex.search(query: "collection OR interface", limit: 10)
        for result in allResults {
            #expect(["swift", "swiftui"].contains(result.framework), "Framework should be extracted from path")
        }

        print("   ✅ Indexed \(allResults.count) documents without metadata.json")
        print("   ✅ Directory scanning test passed!")
    }

    @Test("Directory scanning handles nested framework folders")
    func directoryScanningNestedFolders() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-nested-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Directory scanning with nested folders")

        // Create nested structure: docs/foundation/collections/array.json
        let nestedDir = tempDir.appendingPathComponent("docs/foundation/collections")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let nestedPage = StructuredDocumentationPage(
            url: URL(string: "https://developer.apple.com/documentation/foundation/nsarray")!,
            title: "NSArray",
            kind: .class,
            source: .appleWebKit,
            abstract: "Foundation array class.",
            rawMarkdown: "# NSArray\n\nFoundation array class."
        )
        let nestedDoc = nestedDir.appendingPathComponent("array.json")
        try JSONCoding.encode(nestedPage, to: nestedDoc)

        // Build index
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: nil,
            docsDirectory: tempDir.appendingPathComponent("docs"),
            evolutionDirectory: nil
        )

        try await builder.buildIndex()

        // Verify framework is "foundation" (first folder after docs/)
        let results = try await searchIndex.search(query: "array", limit: 10)
        #expect(!results.isEmpty, "Should find nested documents")
        #expect(results.first?.framework == "foundation", "Should extract framework from first subfolder")

        print("   ✅ Nested folder test passed!")
    }

    // MARK: - Sample Code Catalog Tests

    @Test("Index sample code catalog from bundled resources")
    func indexSampleCodeCatalog() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-sample-code-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Index sample code catalog")

        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: nil,
            docsDirectory: tempDir,
            evolutionDirectory: nil,
            indexSampleCode: true
        )

        try await builder.buildIndex()

        // Verify sample code was indexed
        let sampleResults = try await searchIndex.searchSampleCode(query: "ARKit", limit: 10)
        #expect(!sampleResults.isEmpty, "Should find sample code entries")

        let totalSamples = try await searchIndex.sampleCodeCount()
        #expect(totalSamples > 0, "Should have indexed sample code catalog")
        #expect(totalSamples >= 500, "Should have hundreds of sample code entries")

        print("   ✅ Indexed \(totalSamples) sample code entries")
        print("   ✅ Sample code indexing test passed!")
    }

    @Test("Sample code catalog respects framework filter")
    func sampleCodeFrameworkFilter() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-sample-filter-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Sample code framework filter")

        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: nil,
            docsDirectory: tempDir,
            evolutionDirectory: nil,
            indexSampleCode: true
        )

        try await builder.buildIndex()

        // Search for ARKit samples
        let arkitSamples = try await searchIndex.searchSampleCode(query: "tracking", framework: "ARKit", limit: 10)

        // All results should be ARKit
        for sample in arkitSamples {
            #expect(sample.framework == "ARKit", "Filtered results should match framework")
        }

        print("   ✅ Sample code framework filter working")
        print("   ✅ Framework filter test passed!")
    }

    // MARK: - Package Catalog Tests

    @Test("Index Swift packages catalog from bundled resources")
    func indexPackagesCatalog() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-packages-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Index packages catalog")

        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: nil,
            docsDirectory: tempDir,
            evolutionDirectory: nil
        )

        try await builder.buildIndex()

        // Verify packages were indexed
        let packageResults = try await searchIndex.searchPackages(query: "Alamofire", limit: 10)
        #expect(!packageResults.isEmpty, "Should find package entries")

        let totalPackages = try await searchIndex.packageCount()
        #expect(totalPackages > 0, "Should have indexed packages catalog")
        #expect(totalPackages >= 9000, "Should have thousands of package entries")

        print("   ✅ Indexed \(totalPackages) package entries")
        print("   ✅ Package indexing test passed!")
    }

    @Test("Package catalog includes metadata")
    func packageCatalogMetadata() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-pkg-meta-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Package catalog metadata")

        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: nil,
            docsDirectory: tempDir,
            evolutionDirectory: nil
        )

        try await builder.buildIndex()

        // Search for a well-known package
        let results = try await searchIndex.searchPackages(query: "swift argument parser", limit: 5)
        #expect(!results.isEmpty, "Should find swift-argument-parser")

        if let pkg = results.first {
            #expect(pkg.owner == "apple" || pkg.owner == "Apple", "Should have correct owner")
            #expect(pkg.stars > 0, "Should have star count")
            #expect(pkg.repositoryURL.contains("github.com"), "Should have repository URL")
        }

        print("   ✅ Package metadata verified")
        print("   ✅ Package metadata test passed!")
    }
}
