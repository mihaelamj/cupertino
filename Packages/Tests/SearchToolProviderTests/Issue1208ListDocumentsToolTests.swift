import Foundation
import MCPCore
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

@Suite("#1208 list_documents MCP tool")
struct Issue1208ListDocumentsToolTests {
    /// list_documents now routes through the engine-backed browser the composition root injects
    /// (a reader per source, query-side pluggability). These tests cover the MCP tool layer:
    /// advertisement, delegation + JSON formatting, and that non-apple-docs sources are accepted.
    /// A stub stands in for the engine; per-source listing is covered by CupertinoDataEngine.
    private struct StubBrowsing: Search.DocumentBrowsing {
        let page: Search.DocumentListPage
        func listDocuments(source _: String, framework _: String, offset _: Int, limit _: Int) async throws -> Search.DocumentListPage {
            page
        }

        func listChildren(source: String, uri: String) async throws -> Search.DocumentChildrenPage {
            Search.DocumentChildrenPage(source: source, parentURI: uri, children: [])
        }
    }

    @Test("tools/list advertises list_documents")
    func listToolsAdvertisesListDocuments() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let result = try await provider.listTools(cursor: nil)

        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolListDocuments })
    }

    @Test("list_documents delegates to the injected browser and returns its page as JSON")
    func listDocumentsReturnsJSONPage() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        let expected = Search.DocumentListPage(
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            offset: 1,
            limit: 1,
            total: 2,
            documents: [Search.DocumentListItem(uri: "apple-docs://swiftui/vstack", title: "VStack", kind: "struct")]
        )
        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil, documentBrowsing: StubBrowsing(page: expected))
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolListDocuments,
            arguments: [
                Shared.Constants.Search.schemaParamFramework: MCP.Core.Protocols.AnyCodable("swiftui"),
                Shared.Constants.Search.schemaParamOffset: MCP.Core.Protocols.AnyCodable(1),
                Shared.Constants.Search.schemaParamLimit: MCP.Core.Protocols.AnyCodable(1),
            ]
        )

        guard case let .text(text) = result.content.first else {
            Issue.record("Expected text tool response")
            return
        }
        let page = try JSONDecoder().decode(Search.DocumentListPage.self, from: Data(text.text.utf8))
        #expect(page == expected)
    }

    @Test("list_documents now accepts non-apple-docs sources (query-side pluggability)")
    func listDocumentsAcceptsAllSources() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        // swift-org is no longer rejected: the request routes to the injected per-source browser.
        let expected = Search.DocumentListPage(
            source: Shared.Constants.SourcePrefix.swiftOrg,
            framework: "swift-org",
            offset: 0,
            limit: 50,
            total: 1,
            documents: [Search.DocumentListItem(uri: "swift-org://metadata", title: "Metadata", kind: "article")]
        )
        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil, documentBrowsing: StubBrowsing(page: expected))
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolListDocuments,
            arguments: [
                Shared.Constants.Search.schemaParamFramework: MCP.Core.Protocols.AnyCodable("swift-org"),
                Shared.Constants.Search.schemaParamSource: MCP.Core.Protocols.AnyCodable(Shared.Constants.SourcePrefix.swiftOrg),
            ]
        )
        guard case let .text(text) = result.content.first else {
            Issue.record("Expected text tool response")
            return
        }
        let page = try JSONDecoder().decode(Search.DocumentListPage.self, from: Data(text.text.utf8))
        #expect(page == expected)
    }
}
