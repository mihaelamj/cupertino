import Foundation
import MCPCore
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

@Suite("#1311 unified source-aware `list` tool")
struct Issue1311ListToolTests {
    /// A stub engine browser: canned document page (level 2) + canned children (level 3).
    private struct StubBrowsing: Search.DocumentBrowsing {
        let page: Search.DocumentListPage
        let children: [Search.DocumentChild]
        func listDocuments(source _: String, framework _: String, offset _: Int, limit _: Int) async throws -> Search.DocumentListPage { page }
        func listChildren(source: String, uri: String) async throws -> Search.DocumentChildrenPage {
            Search.DocumentChildrenPage(source: source, parentURI: uri, children: children)
        }
    }

    private static let hierarchies: [String: Search.SourceHierarchy] = [
        "apple-archive": .framework(leafKind: "document"),
        "swift-evolution": .flat(kind: "proposal"),
    ]

    private func makeProvider() async throws -> (CompositeToolProvider, () throws -> Void, any Search.Database) {
        let (index, cleanup) = try await createTestSearchIndex()
        let page = Search.DocumentListPage(
            source: "apple-archive", framework: "foundation", offset: 0, limit: 100, total: 1,
            documents: [Search.DocumentListItem(uri: "apple-archive://10000048i/AboutPropertyLists", title: "About Property Lists", kind: "article")]
        )
        let children = [Search.DocumentChild(uri: "apple-docs://swiftui/view#Essentials", title: "Essentials", kind: "topic-group", hasChildren: true)]
        let provider = CompositeToolProvider(
            searchIndex: index,
            sampleDatabase: nil,
            documentBrowsing: StubBrowsing(page: page, children: children),
            sourceHierarchies: Self.hierarchies,
            sourceFrameworks: { source in source == "apple-archive" ? ["foundation": 170] : [:] }
        )
        return (provider, cleanup, index)
    }

    private func json(_ result: MCP.Core.Protocols.CallToolResult) throws -> [String: Any] {
        guard case let .text(text) = result.content.first else { throw TestFailure.notText }
        let data = Data(text.text.utf8)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private enum TestFailure: Error { case notText }

    @Test("tools/list advertises `list` and keeps `list_frameworks` as an alias")
    func advertised() async throws {
        let (provider, cleanup, index) = try await makeProvider()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }
        let tools = try await provider.listTools(cursor: nil).tools.map(\.name)
        #expect(tools.contains(Shared.Constants.Search.toolList))
        #expect(tools.contains(Shared.Constants.Search.toolListFrameworks))
    }

    @Test("level 0 describes the source hierarchy")
    func describe() async throws {
        let (provider, cleanup, index) = try await makeProvider()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }
        let result = try await provider.callTool(name: Shared.Constants.Search.toolList, arguments: [
            Shared.Constants.Search.schemaParamSource: MCP.Core.Protocols.AnyCodable("swift-evolution"),
        ])
        let obj = try json(result)
        #expect(obj["kind"] as? String == "describe")
        #expect(obj["depth"] as? Int == 1)
        #expect(obj["leafContentType"] as? String == "markdown")
    }

    @Test("level 1 lists the source's OWN frameworks")
    func levelOne() async throws {
        let (provider, cleanup, index) = try await makeProvider()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }
        let result = try await provider.callTool(name: Shared.Constants.Search.toolList, arguments: [
            Shared.Constants.Search.schemaParamSource: MCP.Core.Protocols.AnyCodable("apple-archive"),
            Shared.Constants.Search.schemaParamLevel: MCP.Core.Protocols.AnyCodable(1),
        ])
        let obj = try json(result)
        #expect(obj["level"] as? Int == 1)
        let items = try #require(obj["items"] as? [[String: Any]])
        #expect(items.first?["id"] as? String == "foundation")
        #expect(items.first?["count"] as? Int == 170)
        #expect(items.first?["hasChildren"] as? Bool == true)
    }

    @Test("level 2 lists a framework's documents via the engine browser")
    func levelTwo() async throws {
        let (provider, cleanup, index) = try await makeProvider()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }
        let result = try await provider.callTool(name: Shared.Constants.Search.toolList, arguments: [
            Shared.Constants.Search.schemaParamSource: MCP.Core.Protocols.AnyCodable("apple-archive"),
            Shared.Constants.Search.schemaParamLevel: MCP.Core.Protocols.AnyCodable(2),
            Shared.Constants.Search.schemaParamParent: MCP.Core.Protocols.AnyCodable("foundation"),
        ])
        let obj = try json(result)
        #expect(obj["level"] as? Int == 2)
        #expect(obj["isLeafLevel"] as? Bool == true)
        let items = try #require(obj["items"] as? [[String: Any]])
        #expect(items.first?["id"] as? String == "apple-archive://10000048i/AboutPropertyLists")
    }

    @Test("an out-of-range level is rejected")
    func outOfRange() async throws {
        let (provider, cleanup, index) = try await makeProvider()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }
        await #expect(throws: (any Error).self) {
            _ = try await provider.callTool(name: Shared.Constants.Search.toolList, arguments: [
                Shared.Constants.Search.schemaParamSource: MCP.Core.Protocols.AnyCodable("swift-evolution"),
                Shared.Constants.Search.schemaParamLevel: MCP.Core.Protocols.AnyCodable(2),
            ])
        }
    }
}
