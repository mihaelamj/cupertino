import AppKit
@testable import Core
import Foundation
@testable import MCP
@testable import MCPSupport
@testable import Search
@testable import SearchToolProvider
@testable import Shared
import Testing
import TestSupport

// MARK: - MCP Command Tests

/// Tests for the `cupertino serve` command
/// Verifies server initialization, resource providers, and tool providers

@Suite("MCP Command Tests", .serialized)
struct MCPCommandTests {
    @Test("MCP server initializes successfully")
    func serverInitialization() async throws {
        print("🧪 Test: MCP server initialization")

        _ = MCPServer(name: "test-server", version: "1.0.0")

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

        // Create a test markdown file
        let testFile = tempDir.appendingPathComponent("swift/documentation_swift.md")
        try FileManager.default.createDirectory(
            at: testFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Swift\n\nTest content about Swift language.".write(to: testFile, atomically: true, encoding: .utf8)

        // Create metadata.json for the test file
        let pageMetadata = PageMetadata(
            url: "https://developer.apple.com/documentation/swift",
            framework: "swift",
            filePath: testFile.path,
            contentHash: "test-hash",
            depth: 0
        )
        let metadata = CrawlMetadata(pages: [pageMetadata.url: pageMetadata])
        let metadataFile = tempDir.appendingPathComponent("metadata.json")
        try metadata.save(to: metadataFile)

        let server = MCPServer(name: "test-server", version: "1.0.0")
        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(outputDirectory: tempDir),
            changeDetection: Shared.ChangeDetectionConfiguration(outputDirectory: tempDir),
            output: Shared.OutputConfiguration()
        )
        let provider = DocsResourceProvider(configuration: config)

        await server.registerResourceProvider(provider)

        // List resources
        let listResult = try await provider.listResources(cursor: nil)
        let resources = listResult.resources

        #expect(!resources.isEmpty, "Should have at least one resource")

        if let firstResource = resources.first {
            #expect(firstResource.uri.contains("swift"), "Resource URI should contain framework name")
            print("   ✅ Found resource: \(firstResource.uri)")
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

        // Create test markdown
        let testContent = "# Swift Documentation\n\nThis is test content about the Swift language."
        let testFile = tempDir.appendingPathComponent("swift/documentation_swift.md")
        try FileManager.default.createDirectory(
            at: testFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(outputDirectory: tempDir),
            changeDetection: Shared.ChangeDetectionConfiguration(),
            output: Shared.OutputConfiguration()
        )
        let provider = DocsResourceProvider(configuration: config)

        // Read resource
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

    @Test("Register search tool provider", .tags(.integration), .serialized)
    @MainActor
    func registerSearchProvider() async throws {
        _ = NSApplication.shared

        print("🧪 Test: Register search tool provider")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-search-tool-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create search index with test data
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        // Index a test document
        try await searchIndex.indexDocument(
            uri: "https://developer.apple.com/documentation/swift",
            source: "apple-docs",
            framework: "swift",
            title: "Swift Programming Language",
            content: "Swift is a powerful programming language for iOS, macOS, and more.",
            filePath: "/test/swift.md",
            contentHash: "test-hash",
            lastCrawled: Date()
        )

        let server = MCPServer(name: "test-server", version: "1.0.0")
        let provider = DocumentationToolProvider(searchIndex: searchIndex)

        await server.registerToolProvider(provider)

        // List tools
        let result = try await provider.listTools(cursor: nil)
        let tools = result.tools

        #expect(!tools.isEmpty, "Should have search tools")

        if let searchTool = tools.first(where: { $0.name == "search_docs" }) {
            #expect(searchTool.name == "search_docs", "Should have search_docs tool")
            print("   ✅ Found tool: \(searchTool.name)")
        }

        print("   ✅ Search provider test passed!")
    }

    @Test("Execute search tool", .tags(.integration), .serialized)
    @MainActor
    func executeSearchTool() async throws {
        _ = NSApplication.shared

        print("🧪 Test: Execute search tool")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-search-exec-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create and populate search index
        let searchDbPath = tempDir.appendingPathComponent("search.db")
        let searchIndex = try await Search.Index(dbPath: searchDbPath)

        try await searchIndex.indexDocument(
            uri: "https://developer.apple.com/documentation/swift/array",
            source: "apple-docs",
            framework: "swift",
            title: "Array",
            content: "An ordered, random-access collection of elements.",
            filePath: "/test/array.md",
            contentHash: "test-hash-array",
            lastCrawled: Date()
        )

        let provider = DocumentationToolProvider(searchIndex: searchIndex)

        // Execute search
        let arguments: [String: AnyCodable] = [
            "query": AnyCodable("array"),
            "limit": AnyCodable(5),
        ]

        let result = try await provider.callTool(name: "search_docs", arguments: arguments)

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

        // Create test proposal
        let testProposal = "# SE-0255: Implicit returns from single-expression functions\n\nTest content."
        let testFile = tempDir.appendingPathComponent("SE-0255-omit-return.md")
        try testProposal.write(to: testFile, atomically: true, encoding: .utf8)

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(outputDirectory: tempDir),
            changeDetection: Shared.ChangeDetectionConfiguration(),
            output: Shared.OutputConfiguration()
        )
        let provider = DocsResourceProvider(configuration: config, evolutionDirectory: tempDir)

        // List resources
        let listResult = try await provider.listResources(cursor: nil as String?)
        let resources = listResult.resources

        #expect(!resources.isEmpty, "Should have evolution proposals")

        if let proposal = resources.first {
            #expect(proposal.uri.contains("SE-"), "URI should contain SE- number")
            print("   ✅ Found proposal: \(proposal.uri)")
        }

        // Read resource
        let readResult = try await provider.readResource(uri: "swift-evolution://SE-0255")

        if let firstContent = readResult.contents.first,
           case let .text(textContent) = firstContent {
            #expect(textContent.text.contains("SE-0255"), "Content should contain proposal number")
            print("   ✅ Read proposal content")
        }

        print("   ✅ Evolution provider test passed!")
    }

    @Test("MCP server handles invalid requests gracefully")
    func serverErrorHandling() async throws {
        print("🧪 Test: Server error handling")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-error-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(outputDirectory: tempDir),
            changeDetection: Shared.ChangeDetectionConfiguration(),
            output: Shared.OutputConfiguration()
        )
        let provider = DocsResourceProvider(configuration: config)

        // Try to read non-existent resource
        await #expect(throws: ResourceError.self) {
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
        let stats = try await crawler.crawl()
        #expect(stats.totalPages > 0, "Should have crawled pages")
        print("   ✅ Crawled \(stats.totalPages) page(s)")

        // Step 2: Build index
        print("\n   🔍 Step 2: Building search index...")
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
        print("   ✅ Index built")

        // Step 3: Initialize MCP server
        print("\n   🚀 Step 3: Starting MCP server...")
        let server = MCPServer(name: "test-server", version: "1.0.0")

        // Register providers
        let mcpConfig = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(outputDirectory: tempDir),
            changeDetection: Shared.ChangeDetectionConfiguration(),
            output: Shared.OutputConfiguration()
        )
        let docsProvider = DocsResourceProvider(configuration: mcpConfig)
        let searchProvider = DocumentationToolProvider(searchIndex: searchIndex)

        await server.registerResourceProvider(docsProvider)
        await server.registerToolProvider(searchProvider)
        print("   ✅ Server initialized with providers")

        // Step 4: Search via tool
        print("\n   🔎 Step 4: Searching via MCP tool...")
        let searchArgs: [String: AnyCodable] = [
            "query": AnyCodable("swift"),
            "limit": AnyCodable(5),
        ]
        let searchResults = try await searchProvider.callTool(name: "search_docs", arguments: searchArgs)
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
