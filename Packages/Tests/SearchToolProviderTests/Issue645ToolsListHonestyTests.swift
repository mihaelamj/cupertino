import Foundation
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing
import TestSupport

// MARK: - #645 — MCP tools/list is honest about search.db state

//
// Pre-#645, the CLI composition root passed `nil` for `searchIndex`
// whenever `search.db` failed to open — including the diagnosable
// "file exists but schema mismatch / unopenable" case. The provider
// then silently hid the 7 search.db-dependent tools (list_frameworks,
// read_document, search_symbols, search_property_wrappers,
// search_concurrency, get_inheritance, search_conformances) and
// `tools/list` returned 4 tools (samples-only) or 0. The error never
// reached the AI client; the only signal was "the tool isn't there
// any more", which is indistinguishable from a server downgrade.
//
// Post-#645, `serve` classifies the failure (`SearchIndexLoadResult`)
// and threads a `searchIndexDisabledReason` string into the provider.
// The provider:
//   1. Still advertises the full search-dependent tool surface in
//      `tools/list` so AI agents see what the server is supposed to
//      do.
//   2. Throws a clear error frame from every search.db handler whose
//      message contains the operator-facing reason ("schema mismatch;
//      run `cupertino setup` ..."), mirroring CLI behaviour where
//      the schema-mismatch path prints the same string.
//
// "File missing" (legitimate samples-only deployment) keeps the
// pre-#645 behaviour: tools hidden, no false advertising.

@Suite("CompositeToolProvider tools/list honesty (#645)", .serialized)
struct Issue645ToolsListHonestyTests {
    // MARK: - Surface counts

    @Test("tools/list hides search.db tools when searchIndex is nil AND no disabled reason (legitimate samples-only)")
    func emptySurfaceWhenNothingConfigured() async throws {
        let provider = CompositeToolProvider(searchIndex: nil, sampleDatabase: nil)
        let result = try await provider.listTools(cursor: nil)

        #expect(result.tools.isEmpty)
    }

    @Test("tools/list advertises 9 search.db-dependent tools when reason is set even though searchIndex is nil")
    func reasonOnlyExposesFullSearchSurface() async throws {
        let provider = CompositeToolProvider(
            searchIndex: nil,
            sampleDatabase: nil,
            searchIndexDisabledReason: "schema mismatch; run `cupertino setup` to redownload a matching bundle"
        )
        let result = try await provider.listTools(cursor: nil)

        // 1 unified `search` + 2 list/read + 6 semantic (#665 added
        // `search_generics`) — same set the server would advertise with
        // a healthy index.
        let names = Set(result.tools.map(\.name))
        #expect(names.contains(Shared.Constants.Search.toolSearch))
        #expect(names.contains(Shared.Constants.Search.toolListFrameworks))
        #expect(names.contains(Shared.Constants.Search.toolReadDocument))
        #expect(names.contains(Shared.Constants.Search.toolSearchSymbols))
        #expect(names.contains(Shared.Constants.Search.toolSearchPropertyWrappers))
        #expect(names.contains(Shared.Constants.Search.toolSearchConcurrency))
        #expect(names.contains(Shared.Constants.Search.toolGetInheritance))
        #expect(names.contains(Shared.Constants.Search.toolSearchConformances))
        #expect(names.contains(Shared.Constants.Search.toolSearchGenerics))
        #expect(result.tools.count == 9)
    }

    @Test("tools/list returns full 12 tools when both searchIndex (via reason) and samples are advertised")
    func reasonPlusSamplesExposesEverything() async throws {
        let (database, cleanup) = try await createTestSampleDatabase()
        defer { cleanup() }

        let provider = CompositeToolProvider(
            searchIndex: nil,
            sampleDatabase: database,
            searchIndexDisabledReason: "database unopenable; check the `--search-db` path"
        )
        let result = try await provider.listTools(cursor: nil)

        let names = Set(result.tools.map(\.name))
        // 9 search-side (#665 bumped from 8) + 3 sample-side
        #expect(names.contains(Shared.Constants.Search.toolSearch))
        #expect(names.contains(Shared.Constants.Search.toolListFrameworks))
        #expect(names.contains(Shared.Constants.Search.toolReadDocument))
        #expect(names.contains(Shared.Constants.Search.toolListSamples))
        #expect(names.contains(Shared.Constants.Search.toolReadSample))
        #expect(names.contains(Shared.Constants.Search.toolReadSampleFile))
        #expect(names.contains(Shared.Constants.Search.toolSearchSymbols))
        #expect(names.contains(Shared.Constants.Search.toolSearchPropertyWrappers))
        #expect(names.contains(Shared.Constants.Search.toolSearchConcurrency))
        #expect(names.contains(Shared.Constants.Search.toolGetInheritance))
        #expect(names.contains(Shared.Constants.Search.toolSearchConformances))
        #expect(names.contains(Shared.Constants.Search.toolSearchGenerics))
        #expect(result.tools.count == 12)
    }

    @Test("tools/list returns 4 tools (samples-only) when only samples are configured AND no reason")
    func samplesOnlyWithoutReasonStaysSmall() async throws {
        let (database, cleanup) = try await createTestSampleDatabase()
        defer { cleanup() }

        let provider = CompositeToolProvider(searchIndex: nil, sampleDatabase: database)
        let result = try await provider.listTools(cursor: nil)

        let names = Set(result.tools.map(\.name))
        #expect(names == Set([
            Shared.Constants.Search.toolSearch,
            Shared.Constants.Search.toolListSamples,
            Shared.Constants.Search.toolReadSample,
            Shared.Constants.Search.toolReadSampleFile,
        ]))
    }

    // MARK: - Handler error frames

    /// All 7 search.db-dependent handlers that funnel through
    /// `searchIndexUnavailableError(_:)`. Parameterised so a regression in
    /// any one site fails as a discrete row.
    @Test(
        "search.db handlers throw an error whose message contains the disabled reason",
        arguments: [
            Shared.Constants.Search.toolListFrameworks,
            Shared.Constants.Search.toolReadDocument,
            Shared.Constants.Search.toolSearchSymbols,
            Shared.Constants.Search.toolSearchPropertyWrappers,
            Shared.Constants.Search.toolSearchConcurrency,
            Shared.Constants.Search.toolGetInheritance,
            Shared.Constants.Search.toolSearchConformances,
            Shared.Constants.Search.toolSearchGenerics,
        ]
    )
    func handlersSurfaceDisabledReason(toolName: String) async throws {
        let reason = "schema mismatch; run `cupertino setup` to redownload a matching bundle"
        let provider = CompositeToolProvider(
            searchIndex: nil,
            sampleDatabase: nil,
            searchIndexDisabledReason: reason
        )

        // Minimum required args per tool. Most accept missing args
        // (the handler hits the `guard let searchIndex` before parsing
        // for these specific tools), but provide a value where the
        // handler extracts a required field before the guard.
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamURI: MCP.Core.Protocols.AnyCodable("apple-docs://uikit/uibutton"),
            Shared.Constants.Search.schemaParamSymbol: MCP.Core.Protocols.AnyCodable("UIButton"),
            Shared.Constants.Search.schemaParamWrapper: MCP.Core.Protocols.AnyCodable("State"),
            Shared.Constants.Search.schemaParamPattern: MCP.Core.Protocols.AnyCodable("actor"),
            Shared.Constants.Search.schemaParamProtocol: MCP.Core.Protocols.AnyCodable("Equatable"),
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("Sendable"),
        ]

        await #expect {
            _ = try await provider.callTool(name: toolName, arguments: args)
        } throws: { error in
            guard case let Shared.Core.ToolError.invalidArgument(_, message) = error else {
                return false
            }
            return message.contains("disabled") && message.contains("schema mismatch")
        }
    }

    @Test("handler error frame omits the reason text when no reason is set (file-missing path)")
    func handlerFallbackMessageWithoutReason() async throws {
        let provider = CompositeToolProvider(searchIndex: nil, sampleDatabase: nil)

        await #expect {
            _ = try await provider.callTool(
                name: Shared.Constants.Search.toolListFrameworks,
                arguments: [:]
            )
        } throws: { error in
            guard case let Shared.Core.ToolError.invalidArgument(_, message) = error else {
                return false
            }
            // Pre-#645 cookie-cutter message; preserved verbatim for the
            // legitimate file-missing path so existing tests / clients
            // don't have to special-case the new wording.
            return message == "Documentation index not available"
        }
    }
}
