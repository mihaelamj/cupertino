import ASTIndexer
import Foundation
import LoggingModels
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

// MARK: - #226 — Cross-source partial-filter notice MCP E2E

/// Pre-#226 the MCP `search` tool accepted `min_ios` / `min_macos` /
/// `min_tvos` / `min_watchos` / `min_visionos` and silently ignored them
/// for sources that don't apply the filter (hig / swift-evolution /
/// swift-org / swift-book / apple-archive / samples). An AI client
/// reading the response had no way to know its filter was partially
/// honoured.
///
/// Post-#226 the response carries a stable `platform_filter_partial`
/// marker (Markdown blockquote prepended to the first text-content
/// block) when:
///   - any of the 5 `min_*` args is set, AND
///   - the dispatched source set includes any source that doesn't honour
///     the filter.
///
/// **Layered test strategy** (matches iter-7 / iter-8 / Issue665 pattern):
///
/// - `Issue226PlatformValidationTests` — the validation pure function,
///   decision tree per shape.
/// - `Issue226PlatformFilterScopeTests` (SearchModelsTests) — bucket
///   assignments, partition, dispatchSources, and partialNoticeMarkdown
///   decision tree.
/// - This file — MCP boundary behaviours that go through `callTool` and
///   either (a) fail at parameter validation before dispatch (so no
///   service wiring needed) or (b) hit `prependNoticeIfNeeded` directly.
///   Tests covering "notice fires for source=X" need full service
///   wiring (docsService / sampleService / unifiedService) and are
///   covered at the unit layer above plus the manual smoke against the
///   brew binary documented in the PR.
@Suite("#226 — cross-source partial-filter notice MCP E2E (validation + wiring)")
struct Issue226CrossSourceNoticeMCPMarkerTests {
    private static let marker = "platform_filter_partial"

    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue226-\(UUID().uuidString).db")
    }

    private static func makeProvider() async throws -> (provider: CompositeToolProvider, cleanup: () -> Void) {
        let dbPath = tempDB()
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        return (provider, {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: dbPath)
        })
    }

    // MARK: - Validation rejects malformed input at the MCP boundary

    // Validation runs inside `extractPlatformArgs` which is called by
    // every tool handler before any service dispatch. So even with
    // `docsService` / `sampleService` / `unifiedService` all nil in this
    // test setup, a malformed input throws before reaching them. This
    // pins the validation wiring is in place for every handler in the
    // dispatch table.

    @Test(
        "Validation rejects malformed min_ios values on unified `search` tool",
        arguments: ["", "   ", "v18.0", "18.0a", "ios18", "18..0", ".18", "18."]
    )
    func validationRejectsMalformedOnUnifiedSearch(value: String) async throws {
        let (provider, cleanup) = try await Self.makeProvider()
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamQuery: MCP.Core.Protocols.AnyCodable("color"),
            Shared.Constants.Search.schemaParamMinIOS: MCP.Core.Protocols.AnyCodable(value),
        ]
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.callTool(
                name: Shared.Constants.Search.toolSearch,
                arguments: args
            )
        }
    }

    @Test("Validation also rejects malformed values on 4 AST tools + search_generics")
    func validationOnEveryASTTool() async throws {
        let (provider, cleanup) = try await Self.makeProvider()
        defer { cleanup() }
        let astTools: [String] = [
            Shared.Constants.Search.toolSearchSymbols,
            Shared.Constants.Search.toolSearchPropertyWrappers,
            Shared.Constants.Search.toolSearchConcurrency,
            Shared.Constants.Search.toolSearchConformances,
            Shared.Constants.Search.toolSearchGenerics,
        ]
        for tool in astTools {
            let queryKey = tool == Shared.Constants.Search.toolSearchGenerics
                ? Shared.Constants.Search.schemaParamConstraint
                : Shared.Constants.Search.schemaParamQuery
            let args: [String: MCP.Core.Protocols.AnyCodable] = [
                queryKey: MCP.Core.Protocols.AnyCodable("View"),
                Shared.Constants.Search.schemaParamMinIOS: MCP.Core.Protocols.AnyCodable("v18.0"),
            ]
            await #expect(
                throws: Shared.Core.ToolError.self,
                "tool \(tool) should reject malformed min_ios"
            ) {
                _ = try await provider.callTool(name: tool, arguments: args)
            }
        }
    }

    @Test("Validation rejects malformed values on every min_* parameter")
    func validationOnEveryPlatformParam() async throws {
        let (provider, cleanup) = try await Self.makeProvider()
        defer { cleanup() }
        let paramKeys: [String] = [
            Shared.Constants.Search.schemaParamMinIOS,
            Shared.Constants.Search.schemaParamMinMacOS,
            Shared.Constants.Search.schemaParamMinTvOS,
            Shared.Constants.Search.schemaParamMinWatchOS,
            Shared.Constants.Search.schemaParamMinVisionOS,
        ]
        for key in paramKeys {
            let args: [String: MCP.Core.Protocols.AnyCodable] = [
                Shared.Constants.Search.schemaParamQuery: MCP.Core.Protocols.AnyCodable("View"),
                key: MCP.Core.Protocols.AnyCodable(""),
            ]
            await #expect(
                throws: Shared.Core.ToolError.self,
                "param \(key) should reject empty string"
            ) {
                _ = try await provider.callTool(
                    name: Shared.Constants.Search.toolSearchSymbols,
                    arguments: args
                )
            }
        }
    }

    // MARK: - prependNoticeIfNeeded helper (the wiring point in handleSearch)

    @Test("prependNoticeIfNeeded passes through unchanged when notice is nil")
    func prependNilNoOp() {
        let raw = MCP.Core.Protocols.CallToolResult(content: [
            .text(MCP.Core.Protocols.TextContent(text: "## Results\n\nbody")),
        ])
        let result = CompositeToolProvider.prependNoticeIfNeeded(notice: nil, to: raw)
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text == "## Results\n\nbody")
    }

    @Test("prependNoticeIfNeeded prepends notice to first text block")
    func prependPrependsToFirstText() {
        let raw = MCP.Core.Protocols.CallToolResult(content: [
            .text(MCP.Core.Protocols.TextContent(text: "## Results\n\nbody")),
        ])
        let notice = "> ℹ️ **platform_filter_partial** — test\n\n"
        let result = CompositeToolProvider.prependNoticeIfNeeded(notice: notice, to: raw)
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text.hasPrefix(notice))
        #expect(t.text.contains("## Results"))
    }

    @Test("prependNoticeIfNeeded preserves isError flag")
    func prependPreservesIsError() {
        let raw = MCP.Core.Protocols.CallToolResult(content: [
            .text(MCP.Core.Protocols.TextContent(text: "body")),
        ], isError: true)
        let result = CompositeToolProvider.prependNoticeIfNeeded(notice: "notice\n\n", to: raw)
        #expect(result.isError == true)
    }

    @Test("prependNoticeIfNeeded leaves additional content blocks unchanged")
    func prependLeavesLaterBlocksAlone() {
        let raw = MCP.Core.Protocols.CallToolResult(content: [
            .text(MCP.Core.Protocols.TextContent(text: "first")),
            .text(MCP.Core.Protocols.TextContent(text: "second")),
        ])
        let result = CompositeToolProvider.prependNoticeIfNeeded(notice: "X\n\n", to: raw)
        #expect(result.content.count == 2)
        guard case let .text(t2) = result.content[1] else {
            Issue.record("expected text content at index 1")
            return
        }
        #expect(t2.text == "second", "second block should be untouched")
    }

    @Test("prependNoticeIfNeeded passes through unchanged when first block isn't text")
    func prependSkipsNonTextFirstBlock() {
        // Production handlers always return text first, but defensive
        // behaviour: if a future handler returns image/resource first,
        // skip the prepend rather than crashing or silently dropping.
        let raw = MCP.Core.Protocols.CallToolResult(content: [
            .image(MCP.Core.Protocols.ImageContent(data: "x", mimeType: "image/png")),
            .text(MCP.Core.Protocols.TextContent(text: "fallback")),
        ])
        let result = CompositeToolProvider.prependNoticeIfNeeded(notice: "X\n\n", to: raw)
        // First block stays the image (unchanged), notice silently
        // dropped (not appended elsewhere).
        if case .image = result.content.first {} else {
            Issue.record("first block should remain image")
        }
    }
}
