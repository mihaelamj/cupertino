import Foundation
import MCPCore
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

@Suite("#1210 list_children MCP tool")
struct Issue1210ListChildrenToolTests {
    /// The topic-group parsing now lives in (and is tested by) CupertinoDataEngine; the composition
    /// root injects the engine as the `Search.DocumentChildrenListing`. These tests cover the MCP
    /// tool layer only: that `list_children` is advertised, delegates to the injected listing, and
    /// formats its page as JSON, plus the source-validation guard. A stub stands in for the engine.
    private struct StubChildrenListing: Search.DocumentBrowsing {
        let page: Search.DocumentChildrenPage
        func listChildren(source _: String, uri _: String) async throws -> Search.DocumentChildrenPage {
            page
        }

        func listDocuments(source: String, framework: String, offset: Int, limit: Int) async throws -> Search.DocumentListPage {
            Search.DocumentListPage(source: source, framework: framework, offset: offset, limit: limit, total: 0, documents: [])
        }
    }

    @Test("tools/list advertises list_children")
    func listToolsAdvertisesListChildren() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let result = try await provider.listTools(cursor: nil)

        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolListChildren })
    }

    @Test("list_children delegates to the injected listing and returns its page as JSON")
    func listChildrenReturnsJSONPage() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        let expected = Search.DocumentChildrenPage(
            source: Shared.Constants.SourcePrefix.appleDocs,
            parentURI: "apple-docs://swiftui#Essentials",
            children: [
                Search.DocumentChild(
                    uri: "apple-docs://swiftui/view",
                    title: "View",
                    kind: "protocol",
                    hasChildren: false
                ),
            ]
        )

        let provider = CompositeToolProvider(
            searchIndex: index,
            sampleDatabase: nil,
            documentBrowsing: StubChildrenListing(page: expected)
        )
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolListChildren,
            arguments: [
                Shared.Constants.Search.schemaParamURI: MCP.Core.Protocols.AnyCodable("apple-docs://swiftui#Essentials"),
            ]
        )

        guard case let .text(text) = result.content.first else {
            Issue.record("Expected text tool response")
            return
        }
        let page = try JSONDecoder().decode(
            Search.DocumentChildrenPage.self,
            from: Data(text.text.utf8)
        )

        #expect(page == expected)
    }

    @Test("list_children now accepts non-apple-docs sources (query-side pluggability)")
    func listChildrenAcceptsAllSources() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        // The engine has a reader per source, so the apple-docs-only guard is gone: a
        // swift-org request is routed to the injected browser, not rejected.
        let expected = Search.DocumentChildrenPage(
            source: Shared.Constants.SourcePrefix.swiftOrg,
            parentURI: "swift-org://swift-org",
            children: []
        )
        let provider = CompositeToolProvider(
            searchIndex: index,
            sampleDatabase: nil,
            documentBrowsing: StubChildrenListing(page: expected)
        )

        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolListChildren,
            arguments: [
                Shared.Constants.Search.schemaParamURI: MCP.Core.Protocols.AnyCodable("swift-org://swift-org"),
                Shared.Constants.Search.schemaParamSource: MCP.Core.Protocols.AnyCodable(Shared.Constants.SourcePrefix.swiftOrg),
            ]
        )
        guard case let .text(text) = result.content.first else {
            Issue.record("Expected text tool response")
            return
        }
        let page = try JSONDecoder().decode(Search.DocumentChildrenPage.self, from: Data(text.text.utf8))
        #expect(page == expected)
    }
}
