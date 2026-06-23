import Foundation
import MCPCore
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

/// The unified `list` tool routes catalog sources (samples, packages) through the catalog closures:
/// level 1 enumerates entries (paged across the whole corpus), and levels 2..N walk a file tree by
/// node URI (bare entry id at level 2, full node URI deeper), with directories expandable and files
/// as leaves. Stubs the catalog closures so the routing + URI composition is asserted without a DB.
@Suite("Catalog `list` routing for samples + packages")
struct CatalogListToolTests {
    private static let hierarchies: [String: Search.SourceHierarchy] = [
        "samples": Search.SourceHierarchy(
            levels: [
                .init(level: 1, kind: "project", isLeaf: false),
                .init(level: 2, kind: "file", isLeaf: true),
            ],
            leafContentType: .code
        ),
    ]

    private func makeProvider() -> CompositeToolProvider {
        CompositeToolProvider(
            searchIndex: nil,
            sampleDatabase: nil,
            sourceHierarchies: Self.hierarchies,
            catalogSources: ["samples"],
            catalogEntries: { _, offset, limit in
                Search.CatalogEntryPage(
                    entries: [
                        Search.CatalogEntry(id: "sample-nav", title: "Navigation Sample", fileCount: 3),
                        Search.CatalogEntry(id: "avcam", title: "AVCam", fileCount: 48),
                    ],
                    offset: offset, limit: limit, total: 640
                )
            },
            catalogChildren: { _, parentURI in
                // Echo the received parentURI so the test can assert the URI the tool composed,
                // plus one directory + one file to assert the kind/hasChildren mapping.
                [
                    Search.CatalogNode(uri: "\(parentURI)/Sources", name: "got:\(parentURI)", isDirectory: true),
                    Search.CatalogNode(uri: "\(parentURI)/App.swift", name: "App.swift", isDirectory: false),
                ]
            }
        )
    }

    private func json(_ result: MCP.Core.Protocols.CallToolResult) throws -> [String: Any] {
        guard case let .text(text) = result.content.first else { throw TestFailure.notText }
        return try #require(try JSONSerialization.jsonObject(with: Data(text.text.utf8)) as? [String: Any])
    }

    private func items(_ obj: [String: Any]) throws -> [[String: Any]] {
        try #require(obj["items"] as? [[String: Any]])
    }

    private enum TestFailure: Error { case notText }

    private func call(_ provider: CompositeToolProvider, _ args: [String: Any]) async throws -> [String: Any] {
        var coded: [String: MCP.Core.Protocols.AnyCodable] = [:]
        for (key, value) in args {
            switch value {
            case let int as Int: coded[key] = MCP.Core.Protocols.AnyCodable(int)
            case let string as String: coded[key] = MCP.Core.Protocols.AnyCodable(string)
            case let bool as Bool: coded[key] = MCP.Core.Protocols.AnyCodable(bool)
            default: continue
            }
        }
        return try json(try await provider.callTool(name: Shared.Constants.Search.toolList, arguments: coded))
    }

    @Test("level 1 enumerates entries with the whole-corpus total and file counts")
    func level1() async throws {
        let obj = try await call(makeProvider(), ["source": "samples", "level": 1, "limit": 2])
        #expect(obj["total"] as? Int == 640)
        let items = try items(obj)
        #expect(items.map { $0["title"] as? String } == ["Navigation Sample", "AVCam"])
        #expect(items.first?["hasChildren"] as? Bool == true)
        #expect(items.first?["count"] as? Int == 3)
    }

    @Test("level 2 composes a bare entry id into a scheme URI and maps dir/file nodes")
    func level2() async throws {
        let obj = try await call(makeProvider(), ["source": "samples", "level": 2, "parent": "sample-nav"])
        let items = try items(obj)
        // The bare entry id became `samples://sample-nav`.
        #expect(items.first?["title"] as? String == "got:samples://sample-nav")
        #expect(items.first?["kind"] as? String == "directory")
        #expect(items.first?["hasChildren"] as? Bool == true)
        #expect(items.last?["kind"] as? String == "file")
        #expect(items.last?["hasChildren"] as? Bool == false)
    }

    @Test("level 3 passes a full node URI through unchanged (arbitrary tree depth)")
    func level3() async throws {
        let obj = try await call(makeProvider(), ["source": "samples", "level": 3, "parent": "samples://sample-nav/Sources"])
        let items = try items(obj)
        #expect(items.first?["title"] as? String == "got:samples://sample-nav/Sources")
    }

    @Test("level 0 still describes the source")
    func describe() async throws {
        let obj = try await call(makeProvider(), ["source": "samples"])
        #expect(obj["kind"] as? String == "describe")
    }
}
