import AppKit
@testable import Core
import CoreProtocols
import Crawler
import CrawlerModels
import CrawlerWebKit
import Foundation
import LoggingModels
@testable import MCPCore
@testable import MCPSupport
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
@testable import SearchToolProvider
import SharedConstants
import Testing
import TestSupport

/// 2026-05-28 (Principle 7): the MCP `resources/{list,read}` path is
/// served PURELY from the per-source SQLite DBs. This file-local lookup
/// is the test-side equivalent of the production
/// `LiveMarkdownLookupStrategy` (internal to the CLI target, not
/// importable here): read + list both resolve from a real `Search.Index`
/// with no filesystem access.
private struct IndexBackedLookup: MCP.Support.MarkdownLookupStrategy {
    let dbURL: URL
    let mode: Search.ResourceListMode

    func lookup(uri: String) async throws -> String? {
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        let content = try await index.getDocumentContent(uri: uri, format: .markdown)
        await index.disconnect()
        return content
    }

    func listResources() async throws -> [Search.URIResource] {
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        let entries = try await index.listResourceEntries(mode: mode)
        await index.disconnect()
        return entries
    }
}

// MARK: - Test Doubles

private struct NoopMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
    func convert(markdown: String, url: URL?) -> Shared.Models.StructuredDocumentationPage? {
        nil
    }
}

private struct MissingSampleCatalogProvider: Search.SampleCatalogProvider {
    func fetch() async -> Search.SampleCatalogState {
        .missing(onDiskPath: "")
    }
}

// MARK: - MCP Command Tests

// Tests for the `cupertino serve` command
// Verifies server initialization, resource providers, and tool providers

@Suite("MCP Command Tests", .serialized)
struct MCPCommandTests {
    @Test("MCP server initializes successfully")
    func serverInitialization() {
        print("🧪 Test: MCP server initialization")

        _ = MCP.Core.Server(name: "test-server", version: "1.0.0")

        // Verify server is created (server is a non-optional actor)
        // Simply checking it was instantiated successfully

        print("   ✅ Server initialized!")
    }

    @Test("Register documentation resource provider")
    func registerDocsProvider() async throws {
        print("🧪 Test: Register docs provider")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-mcp-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Build a per-source apple-docs DB with a framework-root row.
        let dbURL = tempDir.appendingPathComponent("apple-documentation.db")
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swift",
            source: "apple-docs",
            framework: "swift",
            title: "Swift",
            content: "Test content about Swift language.",
            filePath: "/n/a",
            contentHash: "test-hash",
            lastCrawled: Date()
        ))
        await index.disconnect()

        let server = MCP.Core.Server(name: "test-server", version: "1.0.0")
        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.appleDocsScheme],
            markdownLookup: IndexBackedLookup(dbURL: dbURL, mode: .frameworkRoots),
            logger: Logging.NoopRecording()
        )

        await server.registerResourceProvider(provider)

        // List resources — DB-backed, no filesystem.
        let listResult = try await provider.listResources(cursor: nil)
        let resources = listResult.resources

        #expect(!resources.isEmpty, "Should have at least one resource")
        let hasSwiftResource = resources.contains { $0.uri.contains("swift") }
        #expect(hasSwiftResource, "Should have at least one resource with 'swift' in URI")
        if let swiftResource = resources.first(where: { $0.uri.contains("swift") }) {
            print("   ✅ Found resource: \(swiftResource.uri)")
        }

        print("   ✅ Docs provider test passed!")
    }

    @Test("Read documentation resource content")
    func readDocsResource() async throws {
        print("🧪 Test: Read docs resource")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-mcp-read-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbURL = tempDir.appendingPathComponent("apple-documentation.db")
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swift/documentation_swift",
            source: "apple-docs",
            framework: "swift",
            title: "Swift Documentation",
            content: "# Swift Documentation\n\nThis is test content about the Swift language.",
            filePath: "/n/a",
            contentHash: "test-hash",
            lastCrawled: Date()
        ))
        await index.disconnect()

        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.appleDocsScheme],
            markdownLookup: IndexBackedLookup(dbURL: dbURL, mode: .allDocuments),
            logger: Logging.NoopRecording()
        )

        // Read resource — resolved from the DB.
        let result = try await provider.readResource(uri: "apple-docs://swift/documentation_swift")

        #expect(!result.contents.isEmpty, "Content should not be empty")

        if let firstContent = result.contents.first,
           case let .text(textContent) = firstContent {
            #expect(textContent.text.contains("Swift Documentation"), "Content should contain title")
            #expect(textContent.text.contains("test content"), "Content should contain body")
            print("   ✅ Read \(textContent.text.count) characters")
        }

        print("   ✅ Read resource test passed!")
    }

    /// `.serialized` removed: the enclosing
    /// `@Suite("MCP Command Tests", .serialized)` already serializes every
    /// test in this suite. `.serialized` on a non-parameterized `@Test`
    /// has no effect and Swift Testing warns about it.
    @Test("Register search tool provider", .tags(.integration))
    @MainActor
    func registerSearchProvider() async throws {
        _ = NSApplication.shared

        print("🧪 Test: Register search tool provider")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-search-tool-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create search index with test data
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(
            dbPath: searchDbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )

        // Index a test document
        try await searchIndex.indexDocument(Search.IndexDocumentParams(
            uri: "https://developer.apple.com/documentation/swift",
            source: "apple-docs",
            framework: "swift",
            title: "Swift Programming Language",
            content: "Swift is a powerful programming language for iOS, macOS, and more.",
            filePath: "/test/swift.md",
            contentHash: "test-hash",
            lastCrawled: Date()
        ))

        let server = MCP.Core.Server(name: "test-server", version: "1.0.0")
        let provider = CompositeToolProvider(searchIndex: searchIndex, sampleDatabase: nil)

        await server.registerToolProvider(provider)

        // List tools
        let result = try await provider.listTools(cursor: nil)
        let tools = result.tools

        #expect(!tools.isEmpty, "Should have search tools")

        if let searchTool = tools.first(where: { $0.name == "search" }) {
            #expect(searchTool.name == "search", "Should have search tool")
            print("   ✅ Found tool: \(searchTool.name)")
        }

        print("   ✅ Search provider test passed!")
    }

    /// `.serialized` removed (same reason as the previous test).
    @Test("Execute search tool", .tags(.integration))
    @MainActor
    func executeSearchTool() async throws {
        _ = NSApplication.shared

        print("🧪 Test: Execute search tool")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-search-exec-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create and populate search index
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(
            dbPath: searchDbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )

        try await searchIndex.indexDocument(Search.IndexDocumentParams(
            uri: "https://developer.apple.com/documentation/swift/array",
            source: "apple-docs",
            framework: "swift",
            title: "Array",
            content: "An ordered, random-access collection of elements.",
            filePath: "/test/array.md",
            contentHash: "test-hash-array",
            lastCrawled: Date()
        ))

        let provider = CompositeToolProvider(searchIndex: searchIndex, sampleDatabase: nil)

        // Execute search
        let arguments: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable("array"),
            "limit": MCP.Core.Protocols.AnyCodable(5),
        ]

        let result = try await provider.callTool(name: "search", arguments: arguments)

        #expect(!result.content.isEmpty, "Search should return results")

        if let firstResult = result.content.first,
           case let .text(textContent) = firstResult {
            #expect(textContent.text.contains("Array"), "Result should contain 'Array'")
            print("   ✅ Search returned: \(textContent.text.prefix(100))...")
        }

        print("   ✅ Search execution test passed!")
    }

    @Test("Swift Evolution resource provider")
    func evolutionResourceProvider() async throws {
        print("🧪 Test: Swift Evolution provider")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-evolution-provider-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbURL = tempDir.appendingPathComponent("swift-evolution.db")
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "swift-evolution://SE-0255",
            source: "swift-evolution",
            framework: "swift-evolution",
            title: "SE-0255: Implicit returns from single-expression functions",
            content: "# SE-0255: Implicit returns\n\nTest content.",
            filePath: "/n/a",
            contentHash: "h",
            lastCrawled: Date()
        ))
        await index.disconnect()

        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.swiftEvolutionScheme],
            markdownLookup: IndexBackedLookup(dbURL: dbURL, mode: .allDocuments),
            logger: Logging.NoopRecording()
        )

        let listResult = try await provider.listResources(cursor: nil as String?)
        let resources = listResult.resources

        #expect(!resources.isEmpty, "Should have evolution proposals")
        let hasProposal = resources.contains { $0.uri.contains("SE-") }
        #expect(hasProposal, "Should have at least one resource with 'SE-' in URI")
        if let proposal = resources.first(where: { $0.uri.contains("SE-") }) {
            print("   ✅ Found proposal: \(proposal.uri)")
        }

        let readResult = try await provider.readResource(uri: "swift-evolution://SE-0255")
        if let firstContent = readResult.contents.first,
           case let .text(textContent) = firstContent {
            #expect(textContent.text.contains("SE-0255"), "Content should contain proposal number")
            print("   ✅ Read proposal content")
        }

        print("   ✅ Evolution provider test passed!")
    }

    @Test("Swift Testing (ST) resource provider lists and reads ST proposals")
    func stResourceProvider() async throws {
        print("🧪 Test: Swift Testing (ST) provider")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-st-provider-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbURL = tempDir.appendingPathComponent("swift-evolution.db")
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "swift-evolution://SE-0255",
            source: "swift-evolution",
            framework: "swift-evolution",
            title: "SE-0255: Implicit returns",
            content: "# SE-0255: Implicit returns\n\nTest content.",
            filePath: "/n/a",
            contentHash: "h-se",
            lastCrawled: Date()
        ))
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "swift-evolution://ST-0001",
            source: "swift-evolution",
            framework: "swift-evolution",
            title: "Refactor Bug Inits",
            content: "# Refactor Bug Inits\n\nSwift Testing proposal about refactoring bug initializers.",
            filePath: "/n/a",
            contentHash: "h-st",
            lastCrawled: Date()
        ))
        await index.disconnect()

        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.swiftEvolutionScheme],
            markdownLookup: IndexBackedLookup(dbURL: dbURL, mode: .allDocuments),
            logger: Logging.NoopRecording()
        )

        // List resources — should include both SE and ST
        let listResult = try await provider.listResources(cursor: nil as String?)
        let resources = listResult.resources

        let hasSEProposal = resources.contains { $0.uri.contains("SE-") }
        let hasSTProposal = resources.contains { $0.uri.contains("ST-") }
        #expect(hasSEProposal, "Should list SE proposals")
        #expect(hasSTProposal, "Should list ST proposals")

        // Read ST resource
        let readResult = try await provider.readResource(uri: "swift-evolution://ST-0001")

        if let firstContent = readResult.contents.first,
           case let .text(textContent) = firstContent {
            #expect(textContent.text.contains("Refactor Bug Inits"), "Content should contain ST proposal title")
            print("   ✅ Read ST proposal content")
        }

        print("   ✅ ST provider test passed!")
    }

    @Test("MCP server handles invalid requests gracefully")
    func serverErrorHandling() async throws {
        print("🧪 Test: Server error handling")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-error-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Empty per-source DB: a read of any URI must throw notFound,
        // with no filesystem fallback.
        let dbURL = tempDir.appendingPathComponent("apple-documentation.db")
        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        await index.disconnect()

        let provider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.appleDocsScheme],
            markdownLookup: IndexBackedLookup(dbURL: dbURL, mode: .frameworkRoots),
            logger: Logging.NoopRecording()
        )

        // Try to read non-existent resource
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.readResource(uri: "apple-docs://nonexistent/file")
        }

        print("   ✅ Error handling test passed!")
    }
}

// MARK: - Integration Test: Full MCP Flow

@Suite("MCP Server Integration", .serialized)
struct MCPServerIntegrationTests {
    @Test("Complete MCP workflow", .tags(.integration, .slow))
    @MainActor
    func completeMCPWorkflow() async throws {
        _ = NSApplication.shared

        print("🧪 Integration Test: Complete MCP workflow")
        print("   This test simulates the full MCP server usage:")
        print("   1. Crawl docs")
        print("   2. Build index")
        print("   3. Start MCP server")
        print("   4. Search via tool")
        print("   5. Read via resource")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-full-mcp-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Step 1: Crawl
        print("\n   📥 Step 1: Crawling documentation...")
        let config = try Shared.Configuration(
            crawler: Shared.Configuration.Crawler(
                startURL: #require(URL(string: "https://developer.apple.com/documentation/swift")),
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.Configuration.ChangeDetection(forceRecrawl: true, outputDirectory: tempDir),
            output: Shared.Configuration.Output(format: .markdown)
        )

        let crawler = await Crawler.AppleDocs(
            configuration: config,
            htmlParser: Crawler.NoopHTMLParserStrategy(),
            appleJSONParser: Crawler.NoopAppleJSONParserStrategy(),
            priorityPackageStrategy: Crawler.NoopPriorityPackageStrategy(),
            fetcherFactory: Crawler.WebKit.LiveHTTPFetcherFactory(),
            logger: Logging.NoopRecording()
        )
        let stats = try await crawler.crawl()
        #expect(stats.totalPages > 0, "Should have crawled pages")
        print("   ✅ Crawled \(stats.totalPages) page(s)")

        // Step 2: Build index
        print("\n   🔍 Step 2: Building search index...")
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(
            dbPath: searchDbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )

        let metadata = try Shared.Models.CrawlMetadata.load(from: tempDir.appendingPathComponent("metadata.json"))
        // #933: inline strategy assembly (factory dissolved).
        let strategies: [any Search.SourceIndexingStrategy] = [
            Search.AppleDocsStrategy(
                docsDirectory: tempDir,
                markdownStrategy: NoopMarkdownStrategy(),
                logger: Logging.NoopRecording()
            ),
        ]
        _ = metadata // pre-#933 factory took this but ignored it
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            strategies: strategies,
            logger: Logging.NoopRecording()
        )
        try await builder.buildIndex()
        // The crawl uses Noop parsers (no network content), so the
        // build may not produce indexable rows. Seed one explicit
        // apple-docs row so Step 5's DB-backed resources/list is
        // deterministic and exercises the read path end-to-end.
        try await searchIndex.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swift",
            source: "apple-docs",
            framework: "swift",
            title: "Swift",
            content: "Swift is a powerful programming language.",
            filePath: "/n/a",
            contentHash: "workflow-seed",
            lastCrawled: Date()
        ))
        print("   ✅ Index built")

        // Step 3: Initialize MCP server
        print("\n   🚀 Step 3: Starting MCP server...")
        let server = MCP.Core.Server(name: "test-server", version: "1.0.0")

        // Register providers. 2026-05-28 (Principle 7): the resource
        // provider reads the SAME `search.db` the index was just built
        // into, via the DB-backed lookup — no filesystem corpus access.
        let docsProvider = MCP.Support.DocsResourceProvider(
            knownURISchemes: [Shared.Constants.Search.appleDocsScheme],
            markdownLookup: IndexBackedLookup(dbURL: searchDbPath, mode: .allDocuments),
            logger: Logging.NoopRecording()
        )
        let searchProvider = CompositeToolProvider(searchIndex: searchIndex, sampleDatabase: nil)

        await server.registerResourceProvider(docsProvider)
        await server.registerToolProvider(searchProvider)
        print("   ✅ Server initialized with providers")

        // Step 4: Search via tool
        print("\n   🔎 Step 4: Searching via MCP tool...")
        let searchArgs: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable("swift"),
            "limit": MCP.Core.Protocols.AnyCodable(5),
        ]
        let searchResults = try await searchProvider.callTool(name: "search", arguments: searchArgs)
        #expect(!searchResults.content.isEmpty, "Search should return results")
        print("   ✅ Search returned results")

        // Step 5: Read via resource
        print("\n   📖 Step 5: Reading via MCP resource...")
        let listResourcesResult = try await docsProvider.listResources(cursor: nil as String?)
        let resources = listResourcesResult.resources
        #expect(!resources.isEmpty, "Should have resources")

        if let firstResource = resources.first {
            let readResult = try await docsProvider.readResource(uri: firstResource.uri)
            #expect(!readResult.contents.isEmpty, "Resource content should not be empty")
            print("   ✅ Read resource: \(firstResource.name)")
        }

        print("\n   🎉 Complete MCP workflow test passed!")
    }
}

// Note: Test tags are now defined in TestSupport/TestTags.swift
