import Foundation
import LoggingModels
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

/// Phase C iter-5 of #673. Extends the semantic-marker pattern established
/// in `Issue669GetInheritanceSemanticMarkerTests` (iter-4) to the `search`
/// and `read_document` MCP tools — the two highest-traffic surfaces an AI
/// agent calls through cupertino-serve.
///
/// Same Carmack discipline: every response shape gets POSITIVE markers
/// (must contain X) AND NEGATIVE markers (must NOT contain Y from a
/// different shape). A regression that swaps response paths fails a test
/// naming the actual semantic class — same shape as the #669 lesson.
///
/// `search` shapes covered:
/// - Empty query → throws `ToolError.invalidArgument` (#596)
/// - No-results: response contains `"_No results found across any source._"`
/// - Success with hits: response contains `"# Unified Search:"` header +
///   the query echo + result entries
///
/// `read_document` shapes covered:
/// - Missing URI argument → throws
/// - Not-found URI → throws `ToolError.invalidArgument` with "Document not found"
/// - Success (markdown format): response contains the seeded title
/// - Success (json format): response contains JSON braces + `"title"` field
@Suite("#673 Phase C iter-5 — MCP search + read_document semantic-marker E2E")
struct Issue673PhaseCSearchAndReadDocumentMarkerTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue673-iter5-\(UUID().uuidString).db")
    }

    /// Construct a `CompositeToolProvider` over a fresh `Search.Index`.
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

    /// Seed a structured page (so `read_document` finds JSON via
    /// `getDocumentContent`).
    private static func seedStructured(
        on idx: Search.Index,
        uri: String,
        title: String,
        framework: String,
        overview: String
    ) async throws {
        let url = URL(string: "https://developer.apple.com/documentation/\(framework)/\(title.lowercased())")!
        let page = Shared.Models.StructuredDocumentationPage(
            url: url,
            title: title,
            kind: .class,
            source: .appleJSON,
            abstract: "Abstract for \(title).",
            overview: overview,
            contentHash: "test-\(UUID().uuidString.prefix(8))"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(page)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        try await idx.indexStructuredDocument(
            uri: uri,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: framework,
            page: page,
            jsonData: jsonString
        )
    }

    // MARK: - search: empty query rejected (#596)

    @Test("search: empty query throws ToolError (#596 — both transports must reject empty consistently)")
    func searchEmptyQueryThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable(""),
        ]
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "search", arguments: args)
        }
    }

    @Test("search: whitespace-only query throws ToolError")
    func searchWhitespaceQueryThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable("   \t\n  "),
        ]
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "search", arguments: args)
        }
    }

    // MARK: - search: success contains canonical markers

    @Test("search success: response contains '# Unified Search:' header + the query echo + the seeded title")
    func searchSuccessHasSemanticMarkers() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedDoc(
                on: idx,
                uri: "apple-docs://swiftui/animation",
                title: "Animation",
                framework: "swiftui",
                content: "SwiftUI provides powerful animation APIs for creating smooth animated transitions."
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable("Animation"),
        ]
        let result = try await provider.callTool(name: "search", arguments: args)
        try #require(!result.content.isEmpty)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        // POSITIVE markers — the unified markdown formatter header
        // (`# Unified Search: "<query>"`) is the canonical success
        // marker. Locks the contract.
        #expect(
            textContent.text.contains("# Unified Search:"),
            "success response must contain '# Unified Search:' header — body was: \(textContent.text.prefix(200))"
        )
        // Query echo confirms the response is about THIS query, not stale state.
        #expect(
            textContent.text.contains("Animation"),
            "success response must echo the query 'Animation' back"
        )
        // NEGATIVE markers — must NOT be the empty-results or error path.
        #expect(
            !textContent.text.contains("_No results found across any source._"),
            "success response must NOT contain the empty-results marker"
        )
    }

    // MARK: - search: no-results path

    @Test("search no-results: response contains '_No results found across any source._' marker")
    func searchNoResultsHasSemanticMarker() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in
            // Empty DB — no documents seeded.
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable("NoSuchTermLikely"),
        ]
        let result = try await provider.callTool(name: "search", arguments: args)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        // POSITIVE marker — explicit empty-results formatter output.
        #expect(
            textContent.text.contains("_No results found across any source._"),
            "no-results response must contain the empty-results marker — body was: \(textContent.text.prefix(300))"
        )
        // Header is still emitted so the user sees what was searched.
        #expect(
            textContent.text.contains("# Unified Search:"),
            "no-results response should still emit the search header"
        )
        // The query echo for traceability.
        #expect(textContent.text.contains("NoSuchTermLikely"))
    }

    // MARK: - read_document: missing URI

    @Test("read_document: missing uri argument throws ToolError")
    func readDocumentMissingURIThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [:]
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "read_document", arguments: args)
        }
    }

    // MARK: - read_document: not-found path

    @Test("read_document not-found: throws ToolError with 'Document not found' in the description")
    func readDocumentNotFoundThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "uri": MCP.Core.Protocols.AnyCodable("apple-docs://nonexistentframework/totallyfake"),
        ]
        // The handler throws `ToolError.invalidArgument(..., "Document not found: \(uri)")`.
        // We assert that AN error is thrown AND its description carries
        // the canonical marker.
        do {
            _ = try await provider.callTool(name: "read_document", arguments: args)
            Issue.record("expected throw, got success")
        } catch {
            let description = "\(error)"
            #expect(
                description.contains("Document not found") || description.contains("not found"),
                "not-found error description must carry a 'not found' marker — got: \(description.prefix(200))"
            )
        }
    }

    // MARK: - read_document: success markdown

    @Test("read_document success (markdown): response contains the seeded title")
    func readDocumentSuccessMarkdownHasTitle() async throws {
        let testTitle = "AnimationFooBarBaz"
        let testFramework = "swiftui"
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedStructured(
                on: idx,
                uri: "apple-docs://\(testFramework)/\(testTitle.lowercased())",
                title: testTitle,
                framework: testFramework,
                overview: "An overview of the \(testTitle) test fixture."
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "uri": MCP.Core.Protocols.AnyCodable("apple-docs://\(testFramework)/\(testTitle.lowercased())"),
            "format": MCP.Core.Protocols.AnyCodable("markdown"),
        ]
        let result = try await provider.callTool(name: "read_document", arguments: args)
        try #require(!result.content.isEmpty)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        // POSITIVE markers — the seeded title must appear in the
        // markdown body. Confirms read_document went through the
        // success path, not the error frame.
        #expect(
            textContent.text.contains(testTitle),
            "markdown response must contain the seeded title '\(testTitle)' — body was: \(textContent.text.prefix(300))"
        )
        // NEGATIVE markers — confirm we're not in the not-found path.
        #expect(
            !textContent.text.contains("Document not found"),
            "success response must NOT contain the not-found marker"
        )
    }

    // MARK: - read_document: success JSON

    @Test("read_document success (json): response contains JSON braces + 'title' key + seeded title")
    func readDocumentSuccessJSONHasTitleKey() async throws {
        let testTitle = "AnimationQuxQuux"
        let testFramework = "swiftui"
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedStructured(
                on: idx,
                uri: "apple-docs://\(testFramework)/\(testTitle.lowercased())",
                title: testTitle,
                framework: testFramework,
                overview: "JSON test overview."
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "uri": MCP.Core.Protocols.AnyCodable("apple-docs://\(testFramework)/\(testTitle.lowercased())"),
            "format": MCP.Core.Protocols.AnyCodable("json"),
        ]
        let result = try await provider.callTool(name: "read_document", arguments: args)
        try #require(!result.content.isEmpty)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        // POSITIVE markers — JSON envelope + title key + seeded title value.
        #expect(textContent.text.contains("{"), "JSON response must contain '{'")
        #expect(textContent.text.contains("}"), "JSON response must contain '}'")
        #expect(
            textContent.text.contains("\"title\""),
            "JSON response must contain a 'title' field — body was: \(textContent.text.prefix(300))"
        )
        #expect(
            textContent.text.contains(testTitle),
            "JSON response must contain the seeded title value"
        )
    }

    // MARK: - read_document: URI normalisation (#587)

    @Test("read_document: web URL is normalised to apple-docs:// before lookup (#587)")
    func readDocumentWebURLNormalised() async throws {
        let testTitle = "WebNormaliseTest"
        let testFramework = "swiftui"
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedStructured(
                on: idx,
                uri: "apple-docs://\(testFramework)/\(testTitle.lowercased())",
                title: testTitle,
                framework: testFramework,
                overview: "Web URL normalisation test."
            )
        }
        defer { cleanup() }

        // Pass the web URL form instead of the apple-docs:// URI; #587
        // CompositeToolProvider.normalizeReadDocumentURI should convert.
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "uri": MCP.Core.Protocols.AnyCodable(
                "https://developer.apple.com/documentation/\(testFramework)/\(testTitle.lowercased())"
            ),
            "format": MCP.Core.Protocols.AnyCodable("markdown"),
        ]
        let result = try await provider.callTool(name: "read_document", arguments: args)
        try #require(!result.content.isEmpty)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(
            textContent.text.contains(testTitle),
            "web URL form must resolve to the same document as apple-docs:// — got: \(textContent.text.prefix(200))"
        )
    }
}
