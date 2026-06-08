import Foundation
import LoggingModels
import SearchModels
@testable import SearchSQLite
import SharedConstants
import Testing

@Suite("#1210 document children")
struct Issue1210DocumentChildrenTests {
    @Test("listChildren returns topic groups for a document root")
    func listChildrenReturnsTopicGroups() async throws {
        let (index, cleanup) = try await makeIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        try await seedSwiftUITree(index)

        let page = try await index.listChildren(
            source: Shared.Constants.SourcePrefix.appleDocs,
            uri: "apple-docs://swiftui"
        )

        #expect(page.source == Shared.Constants.SourcePrefix.appleDocs)
        #expect(page.parentURI == "apple-docs://swiftui")
        #expect(page.children == [
            Search.DocumentChild(
                uri: "apple-docs://swiftui#Essentials",
                title: "Essentials",
                kind: "topic-group",
                hasChildren: true
            ),
            Search.DocumentChild(
                uri: "apple-docs://swiftui#App-structure",
                title: "App structure",
                kind: "topic-group",
                hasChildren: true
            ),
        ])
    }

    @Test("listChildren on a topic-group fragment returns readable documents")
    func listChildrenDrillsIntoTopicGroup() async throws {
        let (index, cleanup) = try await makeIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        try await seedSwiftUITree(index)

        let page = try await index.listChildren(
            source: Shared.Constants.SourcePrefix.appleDocs,
            uri: "apple-docs://swiftui#Essentials"
        )

        #expect(page.parentURI == "apple-docs://swiftui#Essentials")
        #expect(page.children == [
            Search.DocumentChild(
                uri: "apple-docs://swiftui/view",
                title: "View",
                kind: "protocol",
                hasChildren: true
            ),
            Search.DocumentChild(
                uri: "apple-docs://swiftui/view/modifier(_:)",
                title: "modifier(_:)",
                kind: "instance-method",
                hasChildren: false
            ),
        ])
    }

    @Test("listChildren accepts canonical Apple documentation URLs")
    func listChildrenNormalizesAppleDocumentationURL() async throws {
        let (index, cleanup) = try await makeIndex()
        defer { try? cleanup() }
        defer { Task { await index.disconnect() } }

        try await seedSwiftUITree(index)

        let page = try await index.listChildren(
            source: Shared.Constants.SourcePrefix.appleDocs,
            uri: "https://developer.apple.com/documentation/SwiftUI#Essentials"
        )

        #expect(page.parentURI == "apple-docs://swiftui#Essentials")
        #expect(page.children.map(\.uri) == [
            "apple-docs://swiftui/view",
            "apple-docs://swiftui/view/modifier(_:)",
        ])
    }

    private func makeIndex() async throws -> (Search.Index, () throws -> Void) {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-children-\(UUID().uuidString).db")
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        return (index, { try FileManager.default.removeItem(at: dbPath) })
    }

    private func seedSwiftUITree(_ index: Search.Index) async throws {
        let rootMarkdown = """
        # SwiftUI

        ## [Topics](/documentation/swiftui#topics)

        ### [Essentials](/documentation/swiftui#Essentials)

        [View](/documentation/swiftui/view)Create custom views.[modifier(_:)](/documentation/swiftui/view/modifier(_:))Applies a modifier.### [App structure](/documentation/swiftui#App-structure)

        [App](/documentation/swiftui/app)Declare the app entry point.
        """
        let viewMarkdown = """
        # View

        ## [Topics](/documentation/swiftui/view#topics)

        ### [Implementing a custom view](/documentation/swiftui/view#Implementing-a-custom-view)

        [`var body: Self.Body`](/documentation/swiftui/view/body-8kl5o)The content and behavior of the view.
        """

        try await indexDocument(
            index,
            uri: "apple-docs://swiftui",
            title: "SwiftUI",
            kind: "framework",
            rawMarkdown: rootMarkdown
        )
        try await indexDocument(
            index,
            uri: "apple-docs://swiftui/view",
            title: "View",
            kind: "protocol",
            rawMarkdown: viewMarkdown
        )
        try await indexDocument(
            index,
            uri: "apple-docs://swiftui/view/modifier(_:)",
            title: "modifier(_:)",
            kind: "instance-method",
            rawMarkdown: "modifier"
        )
        try await indexDocument(
            index,
            uri: "apple-docs://swiftui/app",
            title: "App",
            kind: "protocol",
            rawMarkdown: "App"
        )
        try await indexDocument(
            index,
            uri: "apple-docs://swiftui/view/body-8kl5o",
            title: "body",
            kind: "instance-property",
            rawMarkdown: "body"
        )
    }

    private func indexDocument(
        _ index: Search.Index,
        uri: String,
        title: String,
        kind: String,
        rawMarkdown: String
    ) async throws {
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: uri,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: title,
            content: rawMarkdown,
            filePath: "/tmp/\(title).json",
            contentHash: uri,
            lastCrawled: Date(),
            sourceType: "apple",
            jsonData: jsonData(title: title, kind: kind, rawMarkdown: rawMarkdown)
        ))
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
