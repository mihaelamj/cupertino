import Foundation
import LoggingModels
import SearchModels
@testable import SearchSQLite
import SharedConstants
import Testing

/// #1146: a non-`--clear` save is incremental. `indexStructuredDocument` skips
/// a doc already in the DB with an unchanged `content_hash`, BEFORE the
/// expensive AST extraction, so an interrupted index resumes and an unchanged
/// re-save is a near no-op. A changed doc (new hash) is still re-indexed.
@Suite("#1146 incremental skip", .serialized)
struct Issue1146IncrementalSkipTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue1146-\(UUID().uuidString).db")
    }

    private static func page(contentHash: String) -> Shared.Models.StructuredDocumentationPage {
        Shared.Models.StructuredDocumentationPage(
            url: URL(string: "https://developer.apple.com/documentation/storekit/product")!,
            title: "Product",
            kind: .struct,
            source: .appleJSON,
            abstract: nil,
            declaration: nil,
            overview: nil,
            sections: [],
            codeExamples: [],
            language: nil,
            crawledAt: Date(),
            contentHash: contentHash
        )
    }

    private static func makeIndexer(at dbPath: URL) async throws -> Search.Indexer {
        try await Search.Indexer(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
    }

    @Test("re-indexing an unchanged doc is skipped (incremental)")
    func unchangedDocSkipped() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Self.makeIndexer(at: dbPath)
        let uri = "apple-docs://storekit/product"

        try await idx.indexStructuredDocument(
            uri: uri, source: "apple-docs", framework: "storekit",
            page: Self.page(contentHash: "hash-1"), jsonData: "{}"
        )
        #expect(try await idx.documentCount() == 1)
        #expect(await idx.incrementalSkips == 0)

        // Same uri, same content hash: skipped before AST extraction.
        try await idx.indexStructuredDocument(
            uri: uri, source: "apple-docs", framework: "storekit",
            page: Self.page(contentHash: "hash-1"), jsonData: "{}"
        )
        #expect(await idx.incrementalSkips == 1)
        #expect(try await idx.documentCount() == 1)
        await idx.disconnect()
    }

    @Test("a changed doc (new content hash) is re-indexed, not skipped")
    func changedDocReindexed() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Self.makeIndexer(at: dbPath)
        let uri = "apple-docs://storekit/product"

        try await idx.indexStructuredDocument(
            uri: uri, source: "apple-docs", framework: "storekit",
            page: Self.page(contentHash: "hash-1"), jsonData: "{}"
        )
        // Same uri, DIFFERENT content hash: re-indexed (INSERT OR REPLACE), not skipped.
        try await idx.indexStructuredDocument(
            uri: uri, source: "apple-docs", framework: "storekit",
            page: Self.page(contentHash: "hash-2"), jsonData: "{}"
        )
        #expect(await idx.incrementalSkips == 0)
        #expect(try await idx.documentCount() == 1)
        await idx.disconnect()
    }
}
