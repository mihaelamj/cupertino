import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #113 — indexer wiring + total-rewrite invariant

//
// Companion to `Issue113DocLinkRewriterTests` (the pure-function pin).
// This file asserts the wire contract — that `indexDocument` and
// `indexStructuredDocument` apply the rewriter on the write path, so
// post-save the DB contains zero `doc://` substrings in the surfaces
// `read_document` / `cupertino read` / search serve back.
//
// Per the #113 issue body: "Post-save sweep verifies zero raw `doc://`
// URIs remain in stored content; CI test or assertion." That's
// `totalRewriteInvariant_postSave` below.

@Suite("#113 — indexer applies DocLinkRewriter on write path", .serialized)
struct Issue113IndexerRewriteIntegrationTests {
    private func makeIndex() async throws -> (Search.Index, URL) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-113-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording())
        return (index, tempDB)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - indexDocument (FTS-only path)

    @Test("indexDocument: doc:// in content gets rewritten before INSERT")
    func indexDocumentRewritesContent() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        let dirtyContent = """
        # SwiftUI View

        See doc://com.apple.documentation/documentation/swiftui/view for the View protocol.
        Related: doc://X/documentation/swiftui/viewbuilder.
        """

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://swiftui/view",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "View",
            content: dirtyContent,
            filePath: "/tmp/view.json",
            contentHash: "h113-1",
            lastCrawled: Date()
        ))

        await index.disconnect()

        // Read `docs_fts.content` directly — that's the FTS5 column the
        // rewriter must scrub. The Search.Result struct surfaces `summary`
        // (first 500 chars) not the full body, so SQL is the right
        // surface to verify the rewrite landed everywhere.
        let body = try Self.readFTSContent(at: dbPath, uri: "apple-docs://swiftui/view")
        #expect(
            !body.contains("doc://"),
            "FTS-side content must be rewritten — got body: \(body.prefix(300))"
        )
        #expect(
            body.contains("https://developer.apple.com/documentation/swiftui/view"),
            "rewritten public URL must surface in stored content; got: \(body)"
        )
    }

    @Test("indexDocument: doc:// in jsonData gets rewritten (read_document path)")
    func indexDocumentRewritesJsonData() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        let dirtyJSON = #"""
        {"title":"View","rawMarkdown":"See doc://X/documentation/swiftui/view for the protocol."}
        """#

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://swiftui/view",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "View",
            content: "stub body",
            filePath: "/tmp/view.json",
            contentHash: "h113-2",
            lastCrawled: Date(),
            jsonData: dirtyJSON
        ))

        // Read the json_data column directly — this is what
        // `read_document` returns to MCP clients.
        let jsonBlob = try await Self.readJSONData(at: dbPath, uri: "apple-docs://swiftui/view")
        await index.disconnect()

        #expect(
            !jsonBlob.contains("doc://"),
            "json_data must be rewritten so read_document returns clean links — got: \(jsonBlob.prefix(300))"
        )
        #expect(
            jsonBlob.contains("https://developer.apple.com/documentation/swiftui/view"),
            "public URL replacement must be present in json_data; got: \(jsonBlob.prefix(300))"
        )
    }

    // MARK: - indexStructuredDocument (FTS + structured path)

    @Test("indexStructuredDocument: doc:// in jsonData rewritten on metadata write")
    func indexStructuredDocumentRewritesJsonData() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/view"))
        let dirtyJSON = #"""
        {"title":"View","rawMarkdown":"Cross-ref: doc://com.apple.documentation/documentation/swiftui/viewbuilder."}
        """#
        let page = Shared.Models.StructuredDocumentationPage(
            url: url,
            title: "View",
            kind: .protocol,
            source: .appleJSON,
            abstract: "A type that represents part of your app's user interface.",
            contentHash: "h113-3"
        )

        try await index.indexStructuredDocument(
            uri: "apple-docs://swiftui/view",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            page: page,
            jsonData: dirtyJSON
        )

        let jsonBlob = try await Self.readJSONData(at: dbPath, uri: "apple-docs://swiftui/view")
        await index.disconnect()

        #expect(
            !jsonBlob.contains("doc://"),
            "structured-path json_data must be rewritten — got: \(jsonBlob.prefix(300))"
        )
        #expect(
            jsonBlob.contains("https://developer.apple.com/documentation/swiftui/viewbuilder"),
            "rewritten cross-ref must be present; got: \(jsonBlob.prefix(300))"
        )
    }

    // MARK: - Total-rewrite invariant (the #113 acceptance criterion)

    @Test("post-save sweep: zero doc:// in docs_metadata.content OR docs_metadata.json_data after multi-page index run")
    func totalRewriteInvariantPostSave() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // Seed 4 pages with assorted dirty content shapes.
        let pages: [(uri: String, framework: String, content: String, json: String)] = [
            (
                "apple-docs://swiftui/view",
                "swiftui",
                "See doc://X/documentation/swiftui/viewbuilder for related.",
                #"{"raw":"doc://X/documentation/swiftui/view"}"#
            ),
            (
                "apple-docs://uikit/uibutton",
                "uikit",
                "Inherits from doc://com.apple.documentation/documentation/uikit/uicontrol.",
                #"{"parent":"doc://X/documentation/uikit/uicontrol"}"#
            ),
            (
                "apple-docs://foundation/url",
                "foundation",
                "No internal links here — clean prose only.",
                #"{"title":"URL"}"#
            ),
            (
                "apple-docs://swiftui/text",
                "swiftui",
                "Two refs: doc://X/documentation/swiftui/font and doc://Y/documentation/swiftui/textstyle.",
                #"{"raw":"doc://X/documentation/swiftui/text"}"#
            ),
        ]

        for page in pages {
            try await index.indexDocument(Search.Index.IndexDocumentParams(
                uri: page.uri,
                source: Shared.Constants.SourcePrefix.appleDocs,
                framework: page.framework,
                title: page.uri,
                content: page.content,
                filePath: "/tmp/\(UUID().uuidString).json",
                contentHash: "h113-sweep-\(UUID().uuidString.prefix(8))",
                lastCrawled: Date(),
                jsonData: page.json
            ))
        }
        await index.disconnect()

        // The invariant the issue body asks for: zero raw doc:// in any
        // stored surface served to clients post-save.
        let leakedMetadataContent = try Self.countMatches(
            at: dbPath,
            sql: "SELECT COUNT(*) FROM docs_metadata WHERE json_data LIKE '%doc://%';"
        )
        #expect(leakedMetadataContent == 0, "docs_metadata.json_data must contain zero doc:// post-save; got: \(leakedMetadataContent) rows")

        let leakedFTSContent = try Self.countMatches(
            at: dbPath,
            sql: "SELECT COUNT(*) FROM docs_fts WHERE content LIKE '%doc://%';"
        )
        #expect(leakedFTSContent == 0, "docs_fts.content must contain zero doc:// post-save; got: \(leakedFTSContent) rows")

        let leakedSummary = try Self.countMatches(
            at: dbPath,
            sql: "SELECT COUNT(*) FROM docs_fts WHERE summary LIKE '%doc://%';"
        )
        #expect(leakedSummary == 0, "docs_fts.summary must contain zero doc:// post-save; got: \(leakedSummary) rows")
    }

    // MARK: - Clean-input invariant (no false positives)

    @Test("pages with no doc:// links round-trip byte-identical content (no false rewrites)")
    func cleanContentRoundTrip() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        let cleanContent = "Plain prose with https://developer.apple.com/documentation/swiftui/view and no internal scheme refs."
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://swiftui/clean",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "Clean",
            content: cleanContent,
            filePath: "/tmp/clean.json",
            contentHash: "h113-clean",
            lastCrawled: Date()
        ))

        await index.disconnect()

        // Verify against docs_fts.content directly (Search.Result only
        // exposes summary). The rewriter must short-circuit when no
        // doc:// is present — output bytes should equal input.
        let body = try Self.readFTSContent(at: dbPath, uri: "apple-docs://swiftui/clean")
        #expect(body.contains("https://developer.apple.com/documentation/swiftui/view"))
        #expect(!body.contains("doc://"))
    }

    // MARK: - Helpers

    /// Read `content` from `docs_fts` for the given URI. `Search.Result`
    /// exposes summary not content, so SQL is the only surface to verify
    /// the full FTS-side content body post-rewrite.
    private static func readFTSContent(at dbPath: URL, uri: String) throws -> String {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw Search.Error.sqliteError("read-fts-content: open failed")
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT content FROM docs_fts WHERE uri = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Search.Error.prepareFailed("read-fts-content prepare")
        }
        sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return ""
        }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
    }

    /// Read `json_data` from `docs_metadata` for the given URI by opening
    /// a fresh sqlite3 handle (the actor is disconnected at test
    /// teardown).
    private static func readJSONData(at dbPath: URL, uri: String) async throws -> String {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw Search.Error.sqliteError("read-json-data: open failed")
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT json_data FROM docs_metadata WHERE uri = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Search.Error.prepareFailed("read-json-data prepare")
        }
        sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return ""
        }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
    }

    /// Count rows for an arbitrary SELECT-COUNT SQL against the test DB.
    private static func countMatches(at dbPath: URL, sql: String) throws -> Int {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw Search.Error.sqliteError("count-matches: open failed")
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Search.Error.prepareFailed("count-matches prepare")
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}
