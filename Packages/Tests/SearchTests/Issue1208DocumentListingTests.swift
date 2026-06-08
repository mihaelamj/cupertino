import Foundation
import LoggingModels
import SearchModels
@testable import SearchSQLite
import SharedConstants
import Testing

@Suite("#1208 document listing")
struct Issue1208DocumentListingTests {
    @Test("listDocuments returns framework-scoped page metadata in deterministic order")
    func listDocumentsPaginatesFrameworkRows() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-documents-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        defer { Task { await index.disconnect() } }

        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://swiftui/zstack",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "ZStack",
            content: "A view that overlays its subviews.",
            filePath: "/tmp/zstack.json",
            contentHash: "zstack",
            lastCrawled: Date(),
            sourceType: "apple",
            jsonData: #"{"title":"ZStack","kind":"struct","rawMarkdown":"ZStack"}"#
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
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://uikit/uiview",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "uikit",
            title: "UIView",
            content: "The base view class.",
            filePath: "/tmp/uiview.json",
            contentHash: "uiview",
            lastCrawled: Date(),
            sourceType: "apple",
            jsonData: #"{"title":"UIView","kind":"class","rawMarkdown":"UIView"}"#
        ))

        let page = try await index.listDocuments(
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "SwiftUI",
            offset: 1,
            limit: 1
        )

        #expect(page.source == Shared.Constants.SourcePrefix.appleDocs)
        #expect(page.framework == "swiftui")
        #expect(page.offset == 1)
        #expect(page.limit == 1)
        #expect(page.total == 2)
        #expect(page.documents == [
            Search.DocumentListItem(
                uri: "apple-docs://swiftui/zstack",
                title: "ZStack",
                kind: "struct"
            ),
        ])
    }

    @Test("listDocuments clamps negative offset and oversized limit")
    func listDocumentsClampsPaging() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-documents-clamp-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let index = try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        defer { Task { await index.disconnect() } }

        let page = try await index.listDocuments(
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            offset: -10,
            limit: Shared.Constants.Limit.maxDocumentListLimit + 99
        )

        #expect(page.offset == 0)
        #expect(page.limit == Shared.Constants.Limit.maxDocumentListLimit)
        #expect(page.total == 0)
        #expect(page.documents.isEmpty)
    }
}
