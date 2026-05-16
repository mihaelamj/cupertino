import Foundation
import LoggingModels
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

/// E2E semantic-marker coverage for `get_inheritance` MCP tool. Phase C of
/// #673. **Directly applies the #669 lesson**: when main retested the
/// v1.2.0 reindex they read a 112-character ERROR response as content
/// (`"No symbol named UIButton in apple-docs..."`), mistaking the failure
/// path for the success path. The fix: every MCP response gets a
/// semantic-marker assertion, not a length check.
///
/// Each response shape produced by `handleGetInheritance` has a distinct
/// semantic marker:
///
/// - **Not found**: contains `"No symbol named"`
/// - **Ambiguous**: contains `"is ambiguous across"` and `"frameworks"`
/// - **No inheritance data**: contains `"_No inheritance data"`
/// - **Real inheritance chain**: contains `"# Inheritance:"` and
///   `"## Inherits from"` or `"## Inherited by"`
///
/// These tests pin each shape so a regression that swaps response paths
/// (e.g. the #669 bug where success path returned the not-found body for
/// every query) fails the test naming the actual semantic class.
@Suite("#669 get_inheritance semantic-marker E2E (Phase C)")
struct Issue669GetInheritanceSemanticMarkerTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue669-mcp-\(UUID().uuidString).db")
    }

    /// Build a `CompositeToolProvider` against a freshly-seeded `Search.Index`
    /// at a temp path. Caller is responsible for calling `cleanup()`.
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

    /// Seed a `StructuredDocumentationPage` with a class declaration so
    /// the AST extractor produces a `doc_symbols` row with the right title
    /// + kind. `resolveSymbolURIs` reads `doc_symbols`, so this is the
    /// minimal seed that makes `get_inheritance` find the class.
    private static func seedClass(
        on idx: Search.Index,
        title: String,
        uri: String,
        framework: String
    ) async throws {
        // Build a page with a class declaration; AST extractor pulls the
        // class symbol with name == `title`, kind = `.class` automatically.
        let url = URL(string: "https://developer.apple.com/documentation/\(framework)/\(title.lowercased())")!
        let page = Shared.Models.StructuredDocumentationPage(
            url: url,
            title: title,
            kind: .class,
            source: .appleJSON,
            declaration: Shared.Models.StructuredDocumentationPage.Declaration(
                code: "class \(title) {}",
                language: "swift"
            ),
            contentHash: "test-\(UUID().uuidString.prefix(8))"
        )
        // Encode the page to JSON so `resolveSymbolURIs` (which reads
        // `json_extract(json_data, '$.title')` against docs_metadata)
        // finds the title row.
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

    // MARK: - Response shape 1: NOT FOUND

    @Test("not-found: response contains the `No symbol named` marker (the #669 false-positive shape)")
    func notFoundHasSemanticMarker() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in
            // Empty DB — no symbols seeded.
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "symbol": MCP.Core.Protocols.AnyCodable("NonexistentBananaType"),
            "direction": MCP.Core.Protocols.AnyCodable("up"),
        ]
        let result = try await provider.callTool(name: "get_inheritance", arguments: args)
        try #require(!result.content.isEmpty)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        // The CRITICAL assertion #669 taught us:
        #expect(
            textContent.text.contains("No symbol named"),
            "not-found response must contain 'No symbol named' — body was: \(textContent.text.prefix(200))"
        )
        #expect(
            textContent.text.contains("NonexistentBananaType"),
            "not-found response should echo the requested symbol back"
        )
        // Negative-side assertion: response must NOT contain success markers.
        #expect(
            !textContent.text.contains("# Inheritance:"),
            "not-found response must NOT contain the success-path header"
        )
        #expect(
            !textContent.text.contains("## Inherits from"),
            "not-found response must NOT contain the success-path inherits header"
        )
    }

    // MARK: - Response shape 2: AMBIGUOUS (multiple frameworks)

    @Test("ambiguous: response contains 'is ambiguous across' + 'frameworks' markers")
    func ambiguousHasSemanticMarker() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            // Two same-named symbols in different frameworks.
            try await Self.seedClass(
                on: idx,
                title: "Color",
                uri: "apple-docs://swiftui/color",
                framework: "swiftui"
            )
            try await Self.seedClass(
                on: idx,
                title: "Color",
                uri: "apple-docs://appkit/nscolorpanel/color",
                framework: "appkit"
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "symbol": MCP.Core.Protocols.AnyCodable("Color"),
            "direction": MCP.Core.Protocols.AnyCodable("up"),
        ]
        let result = try await provider.callTool(name: "get_inheritance", arguments: args)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        // Disambiguation block markers.
        #expect(
            textContent.text.contains("ambiguous across"),
            "ambiguous response must contain 'ambiguous across' — body was: \(textContent.text.prefix(200))"
        )
        #expect(
            textContent.text.contains("frameworks"),
            "ambiguous response must contain 'frameworks'"
        )
        // The candidate list mentions both frameworks.
        #expect(
            textContent.text.contains("swiftui"),
            "ambiguous response should list the swiftui candidate"
        )
        #expect(
            textContent.text.contains("appkit"),
            "ambiguous response should list the appkit candidate"
        )
        // Negative-side: not a success or not-found response.
        #expect(!textContent.text.contains("No symbol named"))
        #expect(!textContent.text.contains("# Inheritance:"))
    }

    // MARK: - Response shape 3: NO INHERITANCE DATA

    @Test("no-edges: response contains '_No inheritance data' marker")
    func noEdgesHasSemanticMarker() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            // Seed the class, but write zero inheritance edges.
            try await Self.seedClass(
                on: idx,
                title: "OrphanClass",
                uri: "apple-docs://test/orphanclass",
                framework: "test"
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "symbol": MCP.Core.Protocols.AnyCodable("OrphanClass"),
            "direction": MCP.Core.Protocols.AnyCodable("up"),
        ]
        let result = try await provider.callTool(name: "get_inheritance", arguments: args)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        // The "no edges" path produces the # Inheritance: header AND the
        // italicised "_No inheritance data" disambiguator below.
        #expect(
            textContent.text.contains("# Inheritance: OrphanClass"),
            "no-edges response should still emit the canonical header"
        )
        #expect(
            textContent.text.contains("_No inheritance data"),
            "no-edges response must contain '_No inheritance data' marker — body was: \(textContent.text.prefix(300))"
        )
        // Suggestion to check conformances (the disambiguation phrase).
        #expect(
            textContent.text.contains("search_conformances"),
            "no-edges response should suggest the search_conformances alternative"
        )
        // Negative-side: not-found and ambiguous shapes are different paths.
        #expect(!textContent.text.contains("No symbol named"))
        #expect(!textContent.text.contains("ambiguous across"))
    }

    // MARK: - Response shape 4: REAL INHERITANCE CHAIN

    @Test("success: response contains '# Inheritance:' + '## Inherits from' markers AND named ancestors")
    func successInheritsFromChainHasSemanticMarkers() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedClass(
                on: idx,
                title: "UIButton",
                uri: "apple-docs://uikit/uibutton",
                framework: "uikit"
            )
            // Edge: UIButton inherits from UIControl.
            try await idx.writeInheritanceEdges(
                pageURI: "apple-docs://uikit/uibutton",
                inheritsFromURIs: ["apple-docs://uikit/uicontrol"],
                inheritedByURIs: nil
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "symbol": MCP.Core.Protocols.AnyCodable("UIButton"),
            "direction": MCP.Core.Protocols.AnyCodable("up"),
        ]
        let result = try await provider.callTool(name: "get_inheritance", arguments: args)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        // Success-path markers:
        #expect(
            textContent.text.contains("# Inheritance: UIButton"),
            "success response must contain '# Inheritance: <Title>' header — body was: \(textContent.text.prefix(300))"
        )
        #expect(
            textContent.text.contains("## Inherits from"),
            "success response with direction=up + non-empty ancestors must contain '## Inherits from' section"
        )
        // Named ancestor present (the semantic content the #669 retest
        // should have asserted on, instead of body length).
        #expect(
            textContent.text.contains("uicontrol") || textContent.text.contains("UIControl"),
            "success response should mention the named ancestor URI/name"
        )
        // Negative-side markers: none of the failure-path shapes.
        #expect(!textContent.text.contains("No symbol named"))
        #expect(!textContent.text.contains("ambiguous across"))
        #expect(!textContent.text.contains("_No inheritance data"))
    }

    @Test("success direction=down: response contains '## Inherited by' marker AND named descendants")
    func successInheritedByChainHasSemanticMarkers() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedClass(
                on: idx,
                title: "UIControl",
                uri: "apple-docs://uikit/uicontrol",
                framework: "uikit"
            )
            // Edge: UIControl inherited by UIButton + UISwitch.
            try await idx.writeInheritanceEdges(
                pageURI: "apple-docs://uikit/uicontrol",
                inheritsFromURIs: nil,
                inheritedByURIs: [
                    "apple-docs://uikit/uibutton",
                    "apple-docs://uikit/uiswitch",
                ]
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "symbol": MCP.Core.Protocols.AnyCodable("UIControl"),
            "direction": MCP.Core.Protocols.AnyCodable("down"),
        ]
        let result = try await provider.callTool(name: "get_inheritance", arguments: args)
        guard case let .text(textContent) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(textContent.text.contains("# Inheritance: UIControl"))
        #expect(
            textContent.text.contains("## Inherited by"),
            "success response with direction=down + non-empty descendants must contain '## Inherited by'"
        )
        #expect(
            textContent.text.contains("uibutton") || textContent.text.contains("UIButton"),
            "descendants list must mention the named UIButton entry"
        )
        #expect(
            textContent.text.contains("uiswitch") || textContent.text.contains("UISwitch"),
            "descendants list must mention the named UISwitch entry"
        )
        #expect(
            !textContent.text.contains("## Inherits from"),
            "direction=down response must NOT contain the up-direction header"
        )
    }

    // MARK: - Argument validation

    @Test("missing symbol argument throws ToolError")
    func missingSymbolThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "direction": MCP.Core.Protocols.AnyCodable("up"),
        ]
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "get_inheritance", arguments: args)
        }
    }

    @Test("invalid direction (sideways) throws ToolError with named directional values")
    func invalidDirectionThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedClass(
                on: idx,
                title: "UIButton",
                uri: "apple-docs://uikit/uibutton",
                framework: "uikit"
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "symbol": MCP.Core.Protocols.AnyCodable("UIButton"),
            "direction": MCP.Core.Protocols.AnyCodable("sideways"),
        ]
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "get_inheritance", arguments: args)
        }
    }

    @Test("depth = 0 throws ToolError (positive depth required)")
    func zeroDepthThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedClass(
                on: idx,
                title: "UIButton",
                uri: "apple-docs://uikit/uibutton",
                framework: "uikit"
            )
        }
        defer { cleanup() }

        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "symbol": MCP.Core.Protocols.AnyCodable("UIButton"),
            "direction": MCP.Core.Protocols.AnyCodable("up"),
            "depth": MCP.Core.Protocols.AnyCodable(0),
        ]
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "get_inheritance", arguments: args)
        }
    }
}
