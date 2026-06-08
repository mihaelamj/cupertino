import Foundation
import MCPCore
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

@Suite("#1210 list_children MCP tool")
struct Issue1210ListChildrenToolTests {
    @Test("tools/list advertises list_children")
    func listToolsAdvertisesListChildren() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let result = try await provider.listTools(cursor: nil)

        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolListChildren })
    }

    @Test("list_children returns a JSON child page")
    func listChildrenReturnsJSONPage() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swiftui",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "SwiftUI",
            content: "SwiftUI",
            filePath: "/tmp/swiftui.json",
            contentHash: "swiftui",
            lastCrawled: Date(),
            sourceType: "apple",
            jsonData: jsonData(
                title: "SwiftUI",
                kind: "framework",
                rawMarkdown: """
                ## [Topics](/documentation/swiftui#topics)

                ### [Essentials](/documentation/swiftui#Essentials)

                [View](/documentation/swiftui/view)Create custom views.
                """
            )
        ))
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swiftui/view",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "View",
            content: "A protocol for views.",
            filePath: "/tmp/view.json",
            contentHash: "view",
            lastCrawled: Date(),
            sourceType: "apple",
            jsonData: jsonData(title: "View", kind: "protocol", rawMarkdown: "View")
        ))

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
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

        #expect(page.source == Shared.Constants.SourcePrefix.appleDocs)
        #expect(page.parentURI == "apple-docs://swiftui#Essentials")
        #expect(page.children == [
            Search.DocumentChild(
                uri: "apple-docs://swiftui/view",
                title: "View",
                kind: "protocol",
                hasChildren: false
            ),
        ])
    }

    @Test("list_children rejects non-apple-docs source until MCP has per-source DB wiring")
    func listChildrenRejectsUnsupportedSource() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)

        await #expect {
            _ = try await provider.callTool(
                name: Shared.Constants.Search.toolListChildren,
                arguments: [
                    Shared.Constants.Search.schemaParamURI: MCP.Core.Protocols.AnyCodable("apple-docs://swiftui"),
                    Shared.Constants.Search.schemaParamSource: MCP.Core.Protocols.AnyCodable(Shared.Constants.SourcePrefix.swiftOrg),
                ]
            )
        } throws: { error in
            guard case let Shared.Core.ToolError.invalidArgument(param, message) = error else {
                return false
            }
            return param == Shared.Constants.Search.schemaParamSource &&
                message.contains("apple-docs")
        }
    }

    private func jsonData(
        title: String,
        kind: String,
        rawMarkdown: String
    ) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "title": title,
            "kind": kind,
            "rawMarkdown": rawMarkdown,
        ], options: [.sortedKeys])
        return try #require(String(data: data, encoding: .utf8))
    }
}
