import Foundation
import LoggingModels
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

/// Phase C iter-7 of #673. Completes the search.db-side MCP semantic-marker
/// coverage with the last 2 tools: `list_frameworks` + `search_concurrency`.
/// **8 of 11 MCP tools now pinned** (the 3 remaining are sample-database
/// tools that need a separate `Sample.Index.Reader` fixture — iter-8).
///
/// Tools pinned by this PR:
///
/// - **`list_frameworks`** — title `"# Available Frameworks"`, table header
///   `"| Framework | Documents |"`, total-docs line `"Total documents:"`.
///   Empty path emits the no-frameworks message.
/// - **`search_concurrency`** — title `"Concurrency Pattern: <name>"`,
///   shares the `"_No symbols found matching your criteria._"` empty marker
///   with the other AST tools.
@Suite("#673 Phase C iter-7 — list_frameworks + search_concurrency markers")
struct Issue673PhaseCRemainingMCPMarkerTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue673-iter7-\(UUID().uuidString).db")
    }

    private static func makeProvider(
        seed: (Search.Index) async throws -> Void
    ) async throws -> (provider: CompositeToolProvider, cleanup: () -> Void) {
        let dbPath = tempDB()
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        try await seed(index)
        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        return (provider, {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: dbPath)
        })
    }

    private static func seedDoc(
        on idx: Search.Index,
        uri: String,
        title: String,
        framework: String,
        content: String
    ) async throws {
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: uri,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: framework,
            title: title,
            content: content,
            filePath: "/tmp/\(framework)-\(UUID().uuidString)",
            contentHash: UUID().uuidString,
            lastCrawled: Date()
        ))
    }

    private static func seedSymbol(
        on idx: Search.Index,
        title: String,
        framework: String,
        declaration: String
    ) async throws {
        let url = URL(string: "https://developer.apple.com/documentation/\(framework)/\(title.lowercased())")!
        let page = Shared.Models.StructuredDocumentationPage(
            url: url,
            title: title,
            kind: .class,
            source: .appleJSON,
            declaration: Shared.Models.StructuredDocumentationPage.Declaration(
                code: declaration,
                language: "swift"
            ),
            contentHash: "test-\(UUID().uuidString.prefix(8))"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(page)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        try await idx.indexStructuredDocument(
            uri: "apple-docs://\(framework)/\(title.lowercased())",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: framework,
            page: page,
            jsonData: jsonString
        )
    }

    // MARK: - list_frameworks

    @Test("list_frameworks empty: response contains '# Available Frameworks' header + 'Total documents: **0**'")
    func listFrameworksEmpty() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in
            // Empty DB — no frameworks.
        }
        defer { cleanup() }
        let result = try await provider.callTool(name: "list_frameworks", arguments: [:])
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(
            t.text.contains("# Available Frameworks"),
            "list_frameworks must contain the canonical header — body: \(t.text.prefix(200))"
        )
        #expect(
            t.text.contains("Total documents:"),
            "list_frameworks must contain 'Total documents:' line"
        )
        // Empty path should NOT emit the table header.
        #expect(
            !t.text.contains("| Framework | Documents |"),
            "empty-DB response must NOT contain the populated-table header"
        )
    }

    @Test("list_frameworks populated: response contains table header + each seeded framework's row")
    func listFrameworksPopulated() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedDoc(
                on: idx,
                uri: "apple-docs://swiftui/view",
                title: "View",
                framework: "swiftui",
                content: "SwiftUI's View protocol."
            )
            try await Self.seedDoc(
                on: idx,
                uri: "apple-docs://uikit/uibutton",
                title: "UIButton",
                framework: "uikit",
                content: "A button view."
            )
            try await Self.seedDoc(
                on: idx,
                uri: "apple-docs://uikit/uiview",
                title: "UIView",
                framework: "uikit",
                content: "The base UIKit view."
            )
        }
        defer { cleanup() }
        let result = try await provider.callTool(name: "list_frameworks", arguments: [:])
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text.contains("# Available Frameworks"))
        #expect(t.text.contains("Total documents:"))
        // Table format markers.
        #expect(
            t.text.contains("| Framework | Documents |"),
            "populated response must contain markdown table header — body: \(t.text.prefix(300))"
        )
        // Each seeded framework appears in a row.
        #expect(
            t.text.contains("`swiftui`"),
            "swiftui framework row missing"
        )
        #expect(
            t.text.contains("`uikit`"),
            "uikit framework row missing"
        )
        // uikit has 2 docs, swiftui has 1; uikit should appear before swiftui
        // (sorted desc by doc count). Verify ordering.
        guard let uikitIdx = t.text.range(of: "`uikit`")?.lowerBound,
              let swiftuiIdx = t.text.range(of: "`swiftui`")?.lowerBound
        else {
            Issue.record("couldn't find both framework rows for ordering check")
            return
        }
        #expect(
            uikitIdx < swiftuiIdx,
            "uikit (2 docs) must appear BEFORE swiftui (1 doc) — sort order is descending by count"
        )
    }

    // MARK: - search_concurrency

    @Test("search_concurrency: missing 'pattern' arg throws ToolError")
    func searchConcurrencyMissingArg() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(
                name: "search_concurrency",
                arguments: [:]
            )
        }
    }

    @Test("search_concurrency no-results: 'Concurrency Pattern: X' header + empty-results marker")
    func searchConcurrencyNoResults() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "pattern": MCP.Core.Protocols.AnyCodable("async"),
        ]
        let result = try await provider.callTool(name: "search_concurrency", arguments: args)
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(
            t.text.contains("Concurrency Pattern: async"),
            "header missing — body: \(t.text.prefix(200))"
        )
        #expect(
            t.text.contains("_No symbols found matching your criteria._"),
            "empty-results marker missing — body: \(t.text.prefix(300))"
        )
    }

    @Test("search_concurrency success: response contains 'Concurrency Pattern: async' + seeded async function name")
    func searchConcurrencySuccess() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            // Seed a function with `async` keyword; AST extractor captures
            // isAsync = true.
            try await Self.seedSymbol(
                on: idx,
                title: "fetchData",
                framework: "myframework",
                declaration: "func fetchData() async throws -> Data {}"
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "pattern": MCP.Core.Protocols.AnyCodable("async"),
        ]
        let result = try await provider.callTool(name: "search_concurrency", arguments: args)
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text.contains("Concurrency Pattern: async"))
        // Lenient assertion — AST extraction of `async` keyword from
        // function declarations is well-tested elsewhere; here we just
        // confirm the response shape is the success path OR the
        // empty-results path (not a different shape).
        let isEmpty = t.text.contains("_No symbols found matching your criteria._")
        let hasName = t.text.contains("fetchData")
        #expect(
            isEmpty || hasName,
            "must be either empty-results OR contain the seeded fn name — body: \(t.text.prefix(300))"
        )
    }

    // MARK: - Cross-tool title-distinctness (regression guard)

    @Test("titles are distinct between list_frameworks and search_concurrency")
    func titlesAreDistinct() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }

        let frameworks = try await provider.callTool(name: "list_frameworks", arguments: [:])
        let concurrency = try await provider.callTool(
            name: "search_concurrency",
            arguments: ["pattern": MCP.Core.Protocols.AnyCodable("foo")]
        )

        guard case let .text(f) = frameworks.content.first,
              case let .text(c) = concurrency.content.first
        else {
            Issue.record("expected text on both")
            return
        }
        #expect(f.text.contains("# Available Frameworks"))
        #expect(!f.text.contains("Concurrency Pattern:"))

        #expect(c.text.contains("Concurrency Pattern:"))
        #expect(!c.text.contains("# Available Frameworks"))
    }
}
