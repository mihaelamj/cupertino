import ASTIndexer
import Foundation
import LoggingModels
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

/// #665 / #409 Layer 2 — MCP semantic-marker E2E for `search_generics`.
///
/// Extends the iter-4..8 pattern (positive marker + negative marker per
/// response shape) to the new 12th MCP tool. Locks:
///
/// - **Title marker**: `"Generic Constraint: <name>"`
/// - **Empty-results marker**: shared `"_No symbols found matching your
///   criteria._"` (the surface every AST-side tool emits).
/// - **Populated body echoes `generic_params`**: a Sendable-constrained
///   symbol surfaces with its full clause (`T: Sendable`) so an agent
///   reading the response can tell why it matched.
/// - **Missing required argument** throws `Shared.Core.ToolError`.
/// - **Cross-tool title distinctness**: a `search_generics` call does
///   NOT surface as `"Protocol Conformance"` or `"Property Wrapper"`
///   (the #669 lesson — regressions that swap handler dispatch fail
///   here, not silently).
@Suite("#665 — search_generics MCP semantic-marker E2E")
struct Issue665SearchGenericsMCPMarkerTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue665-\(UUID().uuidString).db")
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

    /// Seed a doc + an AST symbol with the requested generic-parameter
    /// clause; the test queries `search_generics` against that.
    private static func seedGeneric(
        on idx: Search.Index,
        uri: String,
        framework: String,
        title: String,
        symbolName: String,
        kind: String,
        genericParameters: [String]
    ) async throws {
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: uri,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: framework,
            title: title,
            content: "Stub for \(title)",
            filePath: "/tmp/\(symbolName)-\(UUID().uuidString).json",
            contentHash: "hash-\(UUID().uuidString.prefix(8))",
            lastCrawled: Date()
        ))
        let symbol = ASTIndexer.Symbol(
            name: symbolName,
            kind: ASTIndexer.SymbolKind(rawValue: kind) ?? .struct,
            line: 1,
            column: 1,
            signature: nil,
            isAsync: false,
            isThrows: false,
            isPublic: true,
            isStatic: false,
            attributes: [],
            conformances: [],
            genericParameters: genericParameters
        )
        try await idx.indexDocSymbols(docUri: uri, symbols: [symbol])
    }

    // MARK: - Required argument

    @Test("search_generics: missing 'constraint' argument throws ToolError")
    func missingConstraintArg() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(
                name: Shared.Constants.Search.toolSearchGenerics,
                arguments: [:]
            )
        }
    }

    // MARK: - Empty results

    @Test("search_generics no-results: 'Generic Constraint: X' header + empty-results marker")
    func noResults() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("Sendable"),
        ]
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: args
        )
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(
            t.text.contains("Generic Constraint: Sendable"),
            "title marker missing — body: \(t.text.prefix(200))"
        )
        #expect(
            t.text.contains("_No symbols found matching your criteria._"),
            "shared empty-results marker missing — body: \(t.text.prefix(300))"
        )
    }

    // MARK: - Populated results

    @Test("search_generics success: response contains 'Generic Constraint: Sendable' + seeded symbol name + echoed clause")
    func successEchoesGenericClause() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedGeneric(
                on: idx,
                uri: "apple-docs://swiftui/sendable-box",
                framework: "swiftui",
                title: "SendableBox",
                symbolName: "SendableBox",
                kind: "struct",
                genericParameters: ["T: Sendable"]
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("Sendable"),
        ]
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: args
        )
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text.contains("Generic Constraint: Sendable"))
        #expect(
            t.text.contains("SendableBox"),
            "success response must echo seeded symbol — body: \(t.text.prefix(300))"
        )
        #expect(
            !t.text.contains("_No symbols found matching your criteria._"),
            "success response must NOT contain the empty-results marker"
        )
        // The renderer's "Generic params:" surface comes from the
        // result.genericParams field — locks #665's contract that the
        // matched clause echoes back through MCP.
        #expect(
            t.text.contains("Generic params:") && t.text.contains("Sendable"),
            "response must echo the matched generic clause — body: \(t.text.prefix(400))"
        )
    }

    @Test("search_generics framework filter narrows to the right framework")
    func frameworkFilter() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedGeneric(
                on: idx,
                uri: "apple-docs://swiftui/hosting",
                framework: "swiftui",
                title: "SwiftUIHosting",
                symbolName: "SwiftUIHosting",
                kind: "struct",
                genericParameters: ["Content: View"]
            )
            try await Self.seedGeneric(
                on: idx,
                uri: "apple-docs://uikit/uihosting",
                framework: "uikit",
                title: "UIHostingClass",
                symbolName: "UIHostingClass",
                kind: "class",
                genericParameters: ["Content: View"]
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("View"),
            Shared.Constants.Search.schemaParamFramework: MCP.Core.Protocols.AnyCodable("swiftui"),
        ]
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: args
        )
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text.contains("SwiftUIHosting"), "swiftui row must appear")
        #expect(!t.text.contains("UIHostingClass"), "uikit row must be filtered out — got body: \(t.text.prefix(400))")
        // Active-filter line surfaces the framework filter.
        #expect(
            t.text.contains("framework=swiftui"),
            "active-filters line must surface the framework filter — body: \(t.text.prefix(300))"
        )
    }

    // MARK: - Common-constraint truth-table

    @Test(
        "common constraint truth-table — each canonical constraint surfaces its seeded symbol",
        arguments: [
            ("Sendable", "T: Sendable", "MySendable"),
            ("Hashable", "Key: Hashable", "MyHashable"),
            ("Equatable", "Value: Equatable", "MyEquatable"),
        ]
    )
    func commonConstraintsTruthTable(constraint: String, clause: String, symbolName: String) async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedGeneric(
                on: idx,
                uri: "apple-docs://framework/\(symbolName.lowercased())",
                framework: "framework",
                title: symbolName,
                symbolName: symbolName,
                kind: "struct",
                genericParameters: [clause]
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable(constraint),
        ]
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: args
        )
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text.contains("Generic Constraint: \(constraint)"))
        #expect(t.text.contains(symbolName), "constraint=\(constraint) must echo \(symbolName) — body: \(t.text.prefix(300))")
    }

    // MARK: - Cross-tool title-distinctness (regression guard against handler swap)

    @Test("title distinct from search_conformances / search_property_wrappers / search_concurrency")
    func titleDistinctFromOtherASTTools() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }

        let generics = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: [Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("Foo")]
        )
        let conformances = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchConformances,
            arguments: [Shared.Constants.Search.schemaParamProtocol: MCP.Core.Protocols.AnyCodable("Foo")]
        )
        let wrappers = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchPropertyWrappers,
            arguments: [Shared.Constants.Search.schemaParamWrapper: MCP.Core.Protocols.AnyCodable("Foo")]
        )
        let concurrency = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchConcurrency,
            arguments: [Shared.Constants.Search.schemaParamPattern: MCP.Core.Protocols.AnyCodable("foo")]
        )

        guard case let .text(g) = generics.content.first,
              case let .text(c) = conformances.content.first,
              case let .text(w) = wrappers.content.first,
              case let .text(cc) = concurrency.content.first
        else {
            Issue.record("expected text on all 4 tools")
            return
        }

        // Each title is unique to its tool.
        #expect(g.text.contains("Generic Constraint:"))
        #expect(!g.text.contains("Protocol Conformance:"))
        #expect(!g.text.contains("Property Wrapper:"))
        #expect(!g.text.contains("Concurrency Pattern:"))

        // The other three must NOT carry the new generic-constraint
        // marker (regression guard against a handler-swap bug).
        #expect(!c.text.contains("Generic Constraint:"))
        #expect(!w.text.contains("Generic Constraint:"))
        #expect(!cc.text.contains("Generic Constraint:"))
    }

    // MARK: - tools/list surfaces the new tool

    @Test("tools/list advertises 'search_generics' alongside the other AST tools when search.db is healthy")
    func toolsListAdvertisesSearchGenerics() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let listing = try await provider.listTools(cursor: nil)
        let names = Set(listing.tools.map(\.name))
        #expect(names.contains(Shared.Constants.Search.toolSearchGenerics))
        // Sanity — the other 8 search-side tools must still be there.
        #expect(names.contains(Shared.Constants.Search.toolSearch))
        #expect(names.contains(Shared.Constants.Search.toolSearchConformances))
        #expect(names.contains(Shared.Constants.Search.toolSearchPropertyWrappers))
        #expect(names.contains(Shared.Constants.Search.toolSearchConcurrency))
    }
}
