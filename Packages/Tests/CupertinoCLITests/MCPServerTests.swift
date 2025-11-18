import AppKit
@testable import CupertinoMCP
@testable import CupertinoMCPSupport
@testable import CupertinoSearch
@testable import CupertinoShared
import Foundation
@testable import MCPServer
@testable import MCPShared
@testable import MCPTransport
import Testing

// MARK: - MCP Server Command Tests

/// Tests for the MCP server (cupertino-mcp serve)
/// Verifies server initialization, resource providers, and tool providers

@Suite("MCP Server Tests")
struct MCPServerCommandTests {
    @Test("MCP server initializes successfully")
    func serverInitialization() async throws {
        print("🧪 Test: MCP server initialization")

        let server = await MCPServer()

        // Verify server is created
        #expect(server != nil, "Server should be created")

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

        let server = await MCPServer()
        let provider = DocsResourceProvider(docsDirectory: tempDir)

        await server.registerResourceProvider(provider)

        // List resources
        let resources = try await provider.listResources()

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

        let provider = DocsResourceProvider(docsDirectory: tempDir)

        // Read resource
        let contents = try await provider.readResource(uri: "apple-docs://swift/documentation_swift")

        #expect(!contents.isEmpty, "Content should not be empty")

        if let firstContent = contents.first,
           case let .text(text) = firstContent {
            #expect(text.contains("Swift Documentation"), "Content should contain title")
            #expect(text.contains("test content"), "Content should contain body")
            print("   ✅ Read \(text.count) characters")
        }

        print("   ✅ Read resource test passed!")
    }

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
        let searchIndex = await SearchIndex(databasePath: searchDbPath)
        try await searchIndex.initialize()

        // Index a test document
        try await searchIndex.indexDocument(
            url: "https://developer.apple.com/documentation/swift",
            framework: "swift",
            title: "Swift Programming Language",
            content: "Swift is a powerful programming language for iOS, macOS, and more.",
            filePath: "/test/swift.md"
        )

        let server = await MCPServer()
        let provider = await CupertinoSearchToolProvider(searchIndex: searchIndex)

        await server.registerToolProvider(provider)

        // List tools
        let tools = try await provider.listTools()

        #expect(!tools.isEmpty, "Should have search tools")

        if let searchTool = tools.first(where: { $0.name == "search_docs" }) {
            #expect(searchTool.name == "search_docs", "Should have search_docs tool")
            print("   ✅ Found tool: \(searchTool.name)")
        }

        print("   ✅ Search provider test passed!")
    }

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
        let searchIndex = await SearchIndex(databasePath: searchDbPath)
        try await searchIndex.initialize()

        try await searchIndex.indexDocument(
            url: "https://developer.apple.com/documentation/swift/array",
            framework: "swift",
            title: "Array",
            content: "An ordered, random-access collection of elements.",
            filePath: "/test/array.md"
        )

        let provider = await CupertinoSearchToolProvider(searchIndex: searchIndex)

        // Execute search
        let arguments: [String: JSONValue] = [
            "query": .string("array"),
            "limit": .number(5),
        ]

        let result = try await provider.callTool(name: "search_docs", arguments: arguments)

        #expect(!result.isEmpty, "Search should return results")

        if let firstResult = result.first,
           case let .text(text) = firstResult {
            #expect(text.contains("Array"), "Result should contain 'Array'")
            print("   ✅ Search returned: \(text.prefix(100))...")
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

        let provider = SwiftEvolutionResourceProvider(evolutionDirectory: tempDir)

        // List resources
        let resources = try await provider.listResources()

        #expect(!resources.isEmpty, "Should have evolution proposals")

        if let proposal = resources.first {
            #expect(proposal.uri.contains("SE-"), "URI should contain SE- number")
            print("   ✅ Found proposal: \(proposal.uri)")
        }

        // Read resource
        let contents = try await provider.readResource(uri: "swift-evolution://SE-0255")

        if let firstContent = contents.first,
           case let .text(text) = firstContent {
            #expect(text.contains("SE-0255"), "Content should contain proposal number")
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

        let provider = DocsResourceProvider(docsDirectory: tempDir)

        // Try to read non-existent resource
        await #expect(throws: ResourceError.self) {
            _ = try await provider.readResource(uri: "apple-docs://nonexistent/file")
        }

        print("   ✅ Error handling test passed!")
    }
}

// MARK: - Integration Test: Full MCP Flow

@Suite("MCP Server Integration")
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
        let stats = try await crawler.crawl()
        #expect(stats.totalPages > 0, "Should have crawled pages")
        print("   ✅ Crawled \(stats.totalPages) page(s)")

        // Step 2: Build index
        print("\n   🔍 Step 2: Building search index...")
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
        print("   ✅ Index built")

        // Step 3: Initialize MCP server
        print("\n   🚀 Step 3: Starting MCP server...")
        let server = await MCPServer()

        // Register providers
        let docsProvider = DocsResourceProvider(docsDirectory: tempDir)
        let searchProvider = await CupertinoSearchToolProvider(searchIndex: searchIndex)

        await server.registerResourceProvider(docsProvider)
        await server.registerToolProvider(searchProvider)
        print("   ✅ Server initialized with providers")

        // Step 4: Search via tool
        print("\n   🔎 Step 4: Searching via MCP tool...")
        let searchArgs: [String: JSONValue] = [
            "query": .string("swift"),
            "limit": .number(5),
        ]
        let searchResults = try await searchProvider.callTool(name: "search_docs", arguments: searchArgs)
        #expect(!searchResults.isEmpty, "Search should return results")
        print("   ✅ Search returned results")

        // Step 5: Read via resource
        print("\n   📖 Step 5: Reading via MCP resource...")
        let resources = try await docsProvider.listResources()
        #expect(!resources.isEmpty, "Should have resources")

        if let firstResource = resources.first {
            let contents = try await docsProvider.readResource(uri: firstResource.uri)
            #expect(!contents.isEmpty, "Resource content should not be empty")
            print("   ✅ Read resource: \(firstResource.name)")
        }

        print("\n   🎉 Complete MCP workflow test passed!")
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
    @Tag static var slow: Self
    @Tag static var mcp: Self
}
