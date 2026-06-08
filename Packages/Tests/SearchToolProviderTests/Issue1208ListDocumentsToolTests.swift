import Foundation
import MCPCore
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

@Suite("#1208 list_documents MCP tool")
struct Issue1208ListDocumentsToolTests {
    @Test("tools/list advertises list_documents")
    func listToolsAdvertisesListDocuments() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        let result = try await provider.listTools(cursor: nil)

        #expect(result.tools.contains { $0.name == Shared.Constants.Search.toolListDocuments })
    }

    @Test("list_documents returns a JSON document page")
    func listDocumentsReturnsJSONPage() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swiftui/hstack",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "HStack",
            content: "A view that arranges its subviews horizontally.",
            filePath: "/tmp/hstack.json",
            contentHash: "hstack",
            lastCrawled: Date(),
            sourceType: "apple",
            jsonData: #"{"title":"HStack","kind":"struct","rawMarkdown":"HStack"}"#
        ))
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swiftui/vstack",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "VStack",
            content: "A view that arranges its subviews vertically.",
            filePath: "/tmp/vstack.json",
            contentHash: "vstack",
            lastCrawled: Date(),
            sourceType: "apple",
            jsonData: #"{"title":"VStack","kind":"struct","rawMarkdown":"VStack"}"#
        ))

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
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
        let page = try JSONDecoder().decode(
            Search.DocumentListPage.self,
            from: Data(text.text.utf8)
        )

        #expect(page.source == Shared.Constants.SourcePrefix.appleDocs)
        #expect(page.framework == "swiftui")
        #expect(page.offset == 1)
        #expect(page.limit == 1)
        #expect(page.total == 2)
        #expect(page.documents == [
            Search.DocumentListItem(
                uri: "apple-docs://swiftui/vstack",
                title: "VStack",
                kind: "struct"
            ),
        ])
    }

    @Test("list_documents rejects non-apple-docs source until MCP has per-source DB wiring")
    func listDocumentsRejectsUnsupportedSource() async throws {
        let (index, cleanup) = try await createTestSearchIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)

        await #expect {
            _ = try await provider.callTool(
                name: Shared.Constants.Search.toolListDocuments,
                arguments: [
                    Shared.Constants.Search.schemaParamFramework: MCP.Core.Protocols.AnyCodable("swiftui"),
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
}
