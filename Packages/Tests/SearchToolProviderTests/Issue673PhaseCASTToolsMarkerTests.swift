import Foundation
import LoggingModels
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

/// Phase C iter-6 of #673. Extends the semantic-marker pattern to the
/// **3 AST-side MCP tools** (the same `signalRankOrderClause` surface
/// main hardened in #670 exact-name tier work):
///
/// - `search_symbols` — title `"Symbol Search Results"`
/// - `search_property_wrappers` — title `"Property Wrapper: @<name>"`
/// - `search_conformances` — title `"Protocol Conformance: <name>"`
///
/// All share the same empty-results marker:
/// `"_No symbols found matching your criteria._"`
///
/// Each test asserts on POSITIVE markers + NEGATIVE markers so a regression
/// that swaps response paths (the #669 lesson) fails by name.
@Suite("#673 Phase C iter-6 — MCP AST tools semantic-marker E2E")
struct Issue673PhaseCASTToolsMarkerTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue673-iter6-\(UUID().uuidString).db")
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

    /// Seed a structured page whose declaration code carries
    /// `class X` / `@PropWrapper struct X` / `struct X: Protocol`.
    /// The AST extractor pulls the symbol + its attributes / conformances
    /// into `doc_symbols` so the AST tool queries find it.
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

    // MARK: - search_symbols

    @Test("search_symbols no-results: '_No symbols found matching your criteria._' marker + 'Symbol Search Results' title")
    func searchSymbolsNoResults() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable("DefinitelyNoMatch"),
        ]
        let result = try await provider.callTool(name: "search_symbols", arguments: args)
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        #expect(
            t.text.contains("Symbol Search Results"),
            "title marker missing — body: \(t.text.prefix(200))"
        )
        #expect(
            t.text.contains("_No symbols found matching your criteria._"),
            "empty-results marker missing — body: \(t.text.prefix(200))"
        )
    }

    @Test("search_symbols success: response contains 'Symbol Search Results' + seeded symbol name")
    func searchSymbolsSuccess() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedSymbol(
                on: idx,
                title: "MySpecialClass",
                framework: "swiftui",
                declaration: "class MySpecialClass {}"
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable("MySpecial"),
        ]
        let result = try await provider.callTool(name: "search_symbols", arguments: args)
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        #expect(t.text.contains("Symbol Search Results"))
        #expect(
            t.text.contains("MySpecialClass"),
            "success response must echo seeded symbol — body: \(t.text.prefix(300))"
        )
        #expect(
            !t.text.contains("_No symbols found matching your criteria._"),
            "success response must NOT contain the empty-results marker"
        )
    }

    // MARK: - search_property_wrappers

    @Test("search_property_wrappers: missing 'wrapper' argument throws ToolError")
    func searchPropertyWrappersMissingArg() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(
                name: "search_property_wrappers",
                arguments: [:]
            )
        }
    }

    @Test("search_property_wrappers no-results: 'Property Wrapper: @X' header + empty-results marker")
    func searchPropertyWrappersNoResults() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "wrapper": MCP.Core.Protocols.AnyCodable("NonExistentWrapper"),
        ]
        let result = try await provider.callTool(name: "search_property_wrappers", arguments: args)
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        // Title carries the normalised @-prefixed form (NonExistentWrapper → @NonExistentWrapper).
        #expect(
            t.text.contains("Property Wrapper: @NonExistentWrapper"),
            "normalised title missing — body: \(t.text.prefix(200))"
        )
        #expect(t.text.contains("_No symbols found matching your criteria._"))
    }

    @Test("search_property_wrappers: input with @ prefix is preserved (not double-@d)")
    func searchPropertyWrappersAtPrefixPreserved() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "wrapper": MCP.Core.Protocols.AnyCodable("@MainActor"),
        ]
        let result = try await provider.callTool(name: "search_property_wrappers", arguments: args)
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        // Header should be exactly "@MainActor", not "@@MainActor".
        #expect(
            t.text.contains("Property Wrapper: @MainActor"),
            "@-prefixed input should not be double-prefixed — body: \(t.text.prefix(200))"
        )
        #expect(
            !t.text.contains("@@"),
            "must NOT double-prefix the @ symbol"
        )
    }

    // MARK: - search_conformances

    @Test("search_conformances: missing 'protocol' argument throws ToolError")
    func searchConformancesMissingArg() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(
                name: "search_conformances",
                arguments: [:]
            )
        }
    }

    @Test("search_conformances no-results: 'Protocol Conformance: X' header + empty-results marker")
    func searchConformancesNoResults() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "protocol": MCP.Core.Protocols.AnyCodable("Sendable"),
        ]
        let result = try await provider.callTool(name: "search_conformances", arguments: args)
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        #expect(
            t.text.contains("Protocol Conformance: Sendable"),
            "header missing — body: \(t.text.prefix(200))"
        )
        #expect(t.text.contains("_No symbols found matching your criteria._"))
    }

    @Test("search_conformances success: response echoes seeded conformer name")
    func searchConformancesSuccess() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            // Seed a struct that conforms to Sendable; AST extractor
            // captures the `Sendable` token in conformances.
            try await Self.seedSymbol(
                on: idx,
                title: "MySendableType",
                framework: "swiftui",
                declaration: "struct MySendableType: Sendable {}"
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "protocol": MCP.Core.Protocols.AnyCodable("Sendable"),
        ]
        let result = try await provider.callTool(name: "search_conformances", arguments: args)
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        #expect(t.text.contains("Protocol Conformance: Sendable"))
        // Either the type appears (full success) OR the empty marker (if
        // AST extraction didn't capture the conformance — possible with
        // very minimal declarations). Locks the contract either way.
        if t.text.contains("_No symbols found matching your criteria._") {
            Issue.record("conformance extraction may not handle inline 'struct X: Protocol {}' shape; consider seeding with explicit conformsTo")
        } else {
            #expect(
                t.text.contains("MySendableType"),
                "non-empty response must echo seeded conformer — body: \(t.text.prefix(300))"
            )
        }
    }

    // MARK: - cross-tool: all 3 produce different titles for the same no-results condition

    @Test("titles are distinct across the 3 AST tools (regression guard against handler swaps)")
    func titlesAreDistinct() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }

        // search_symbols
        let symbols = try await provider.callTool(
            name: "search_symbols",
            arguments: ["query": MCP.Core.Protocols.AnyCodable("Foo")]
        )
        // search_property_wrappers
        let wrappers = try await provider.callTool(
            name: "search_property_wrappers",
            arguments: ["wrapper": MCP.Core.Protocols.AnyCodable("Foo")]
        )
        // search_conformances
        let conformances = try await provider.callTool(
            name: "search_conformances",
            arguments: ["protocol": MCP.Core.Protocols.AnyCodable("Foo")]
        )

        guard case let .text(s) = symbols.content.first,
              case let .text(w) = wrappers.content.first,
              case let .text(c) = conformances.content.first
        else {
            Issue.record("expected text contents on all 3")
            return
        }
        // Each tool's title is unique — a regression that swaps the
        // handlers would surface as wrong title for the response.
        #expect(s.text.contains("Symbol Search Results"))
        #expect(!s.text.contains("Property Wrapper:"))
        #expect(!s.text.contains("Protocol Conformance:"))

        #expect(w.text.contains("Property Wrapper:"))
        #expect(!w.text.contains("Symbol Search Results"))
        #expect(!w.text.contains("Protocol Conformance:"))

        #expect(c.text.contains("Protocol Conformance:"))
        #expect(!c.text.contains("Symbol Search Results"))
        #expect(!c.text.contains("Property Wrapper:"))
    }
}
