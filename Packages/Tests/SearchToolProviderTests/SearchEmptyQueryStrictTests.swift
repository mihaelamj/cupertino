import Foundation
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing
import TestSupport

// MARK: - #596 — MCP search rejects empty / whitespace-only query
//
// Pre-#596, the MCP `search` tool returned a 620-char "no results"
// content payload (exit 0) for `query=""`, while CLI `cupertino
// search ""` exited 1 with a usage error. Same logical input, two
// transports diverging — forced clients to handle two distinct
// response shapes for the same empty-query case.
//
// Post-#596, MCP rejects empty / whitespace-only queries with
// `Shared.Core.ToolError.invalidArgument("query", "Query cannot
// be empty")`, which the JSON-RPC layer surfaces as a -32602
// invalidParams error frame. CLI behaviour is unchanged.

@Suite("CompositeToolProvider search empty-query rejection (#596)")
struct SearchEmptyQueryStrictTests {
    private func makeProvider() -> CompositeToolProvider {
        // No real index needed — the empty-query guard fires before
        // the search backend ever runs. Pass nil for both.
        CompositeToolProvider(searchIndex: nil, sampleDatabase: nil)
    }

    @Test(
        "empty / whitespace-only queries throw invalidArgument",
        arguments: ["", " ", "   ", "\t", "\n", "\t\n  ", "\r\n"]
    )
    func emptyOrWhitespaceQueryThrows(query: String) async {
        let provider = makeProvider()
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable(query),
        ]
        await #expect(throws: Shared.Core.ToolError.self) {
            _ = try await provider.callTool(name: "search", arguments: args)
        }
    }

    @Test("error carries the schemaParamQuery field name + clear message")
    func errorShape() async {
        let provider = makeProvider()
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable(""),
        ]
        await #expect {
            _ = try await provider.callTool(name: "search", arguments: args)
        } throws: { error in
            guard case let Shared.Core.ToolError.invalidArgument(field, message) = error else {
                return false
            }
            return field == Shared.Constants.Search.schemaParamQuery
                && message.contains("empty")
        }
    }

    @Test("Single character query passes the empty-query guard")
    func singleCharQueryProceeds() async {
        // The guard must only reject EMPTY / whitespace-only queries.
        // "a" is non-empty after trimming and must proceed (it will
        // hit the next guard — searchIndex is nil — and throw a
        // different error, but it must NOT throw the 'Query cannot
        // be empty' error).
        let provider = makeProvider()
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable("a"),
        ]
        await #expect {
            _ = try await provider.callTool(name: "search", arguments: args)
        } throws: { error in
            // Must NOT be the empty-query error. Any other error
            // (including invalidArgument for missing index) is fine.
            if case let Shared.Core.ToolError.invalidArgument(field, message) = error,
               field == Shared.Constants.Search.schemaParamQuery,
               message.contains("empty") {
                return false
            }
            return true
        }
    }
}
