import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

/// Regression suite for [#607](https://github.com/mihaelamj/cupertino/issues/607)
/// read-side fallback half.
///
/// PR #608 (indexer half) inlines `params.content` into the synthesised
/// `docs_metadata.json_data` wrapper for new saves. Bundles shipped before
/// that PR carry rows where the wrapper has `rawMarkdown: null` but the
/// full body lives in `docs_fts.content` — `cupertino setup` users on
/// v1.0.x / v1.1.x bundles need the read path to merge those two sides
/// without re-indexing. The fallback lives in
/// `Search.Index.getDocumentContent(uri:format: .json)` and delegates the
/// inspect-and-merge to
/// `Search.Index.mergeFTSContentIfRawMarkdownMissing(uri:jsonString:)`.
@Suite("#607 read-side fallback: JOIN docs_fts.content when rawMarkdown is null", .serialized)
struct ReadDocumentFTSFallbackTests {
    @Test("getDocumentContent .json merges FTS content when wrapper has rawMarkdown:null")
    func mergeFTSWhenRawMarkdownNull() async throws {
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        // Bootstrap an empty DB so the schema exists, then OVERWRITE the
        // metadata row to simulate the pre-#608 wrapper shape (with
        // `rawMarkdown: null`). The FTS row, written by `indexDocument`
        // up front, already carries the full body.
        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())

        let body = "## Heading\n\nFull body with \"quotes\" and a backslash \\ and a backtick `."
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "swift-evolution://SE-0304",
            source: "swift-evolution",
            framework: nil,
            title: "Structured concurrency",
            content: body,
            filePath: "/tmp/SE-0304.md",
            contentHash: "deadbeef",
            lastCrawled: Date()
            // jsonData: nil — post-#608 this writes the body INTO json_data.
        ))
        await index.disconnect()

        // Simulate the pre-#608 corpus by overwriting the wrapper to its
        // legacy shape.
        try Self.overwriteJsonData(
            at: dbURL,
            uri: "swift-evolution://SE-0304",
            jsonString: #"{"title":"Structured concurrency","url":"swift-evolution://SE-0304","rawMarkdown":null,"source":"swift-evolution","framework":""}"#
        )

        // Re-open and ask the read path for the document.
        let index2 = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
        let returned = try await index2.getDocumentContent(uri: "swift-evolution://SE-0304", format: .json)
        await index2.disconnect()

        let jsonString = try #require(returned)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any]
        )
        // Read path injected the FTS body back into the wrapper.
        #expect(payload["rawMarkdown"] as? String == body)
        // Other wrapper fields preserved.
        #expect(payload["title"] as? String == "Structured concurrency")
        #expect(payload["url"] as? String == "swift-evolution://SE-0304")
        #expect(payload["source"] as? String == "swift-evolution")
    }

    @Test("getDocumentContent .json returns wrapper verbatim when rawMarkdown is already populated")
    func noMergeWhenRawMarkdownAlreadyPresent() async throws {
        // The post-#608 indexer writes the body into rawMarkdown. The
        // read-side merge must NOT touch the wrapper in that case;
        // re-serialisation would lose any non-trivial field order or
        // formatting the indexer chose to preserve.
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())

        let body = "Body is here."
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "hig://components/buttons",
            source: "hig",
            framework: "components",
            title: "Buttons",
            content: body,
            filePath: "/tmp/buttons.md",
            contentHash: "feedface",
            lastCrawled: Date()
        ))

        // The indexer wrote a wrapper that already carries `rawMarkdown`.
        let returned = try await index.getDocumentContent(uri: "hig://components/buttons", format: .json)
        await index.disconnect()

        let jsonString = try #require(returned)
        // Read path noticed rawMarkdown was already populated and returned
        // the wrapper unchanged.
        let payload = try #require(
            try JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any]
        )
        #expect(payload["rawMarkdown"] as? String == body)
    }

    @Test("Empty rawMarkdown string counts as missing — fallback fires")
    func emptyRawMarkdownTriggersFallback() async throws {
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
        let body = "Real body."
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-archive://10000047i/RevisionHistory",
            source: "apple-archive",
            framework: "Foundation",
            title: "Revision History",
            content: body,
            filePath: "/tmp/rev.md",
            contentHash: "cafebabe",
            lastCrawled: Date()
        ))
        await index.disconnect()

        // Overwrite the wrapper so rawMarkdown is an empty string (not null,
        // not missing). The fallback should still fire because the spec is
        // "rawMarkdown is not a non-empty String".
        try Self.overwriteJsonData(
            at: dbURL,
            uri: "apple-archive://10000047i/RevisionHistory",
            jsonString: #"{"title":"Revision History","url":"apple-archive://10000047i/RevisionHistory","rawMarkdown":"","source":"apple-archive","framework":"Foundation"}"#
        )

        let index2 = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
        let returned = try await index2.getDocumentContent(uri: "apple-archive://10000047i/RevisionHistory", format: .json)
        await index2.disconnect()

        let jsonString = try #require(returned)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any]
        )
        #expect(payload["rawMarkdown"] as? String == body)
    }

    @Test("Unparseable stored wrapper falls back to verbatim — no crash, no merge attempt")
    func unparseableWrapperReturnsVerbatim() async throws {
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "swift-evolution://SE-0001",
            source: "swift-evolution",
            framework: nil,
            title: "First",
            content: "body",
            filePath: "/tmp/SE-0001.md",
            contentHash: "01",
            lastCrawled: Date()
        ))
        await index.disconnect()

        // Plant a malformed JSON string in json_data. The read path must
        // not crash; it must just hand back the stored value.
        let malformed = "{not even JSON"
        try Self.overwriteJsonData(at: dbURL, uri: "swift-evolution://SE-0001", jsonString: malformed)

        let index2 = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
        let returned = try await index2.getDocumentContent(uri: "swift-evolution://SE-0001", format: .json)
        await index2.disconnect()

        #expect(returned == malformed)
    }

    // MARK: - Helpers

    private static func makeTempDB() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "search-#607-read-\(UUID().uuidString).db"
        )
    }

    /// Replace the `json_data` of the row whose `uri` matches. Used to
    /// simulate pre-#608 bundles by stripping `rawMarkdown` from the
    /// wrapper after the indexer has populated `docs_fts.content`.
    private static func overwriteJsonData(at dbURL: URL, uri: String, jsonString: String) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 1)
        }
        let sql = "UPDATE docs_metadata SET json_data = ? WHERE uri = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(
                domain: "TestSetup", code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
            )
        }
        sqlite3_bind_text(stmt, 1, (jsonString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (uri as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(
                domain: "TestSetup", code: 3,
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
            )
        }
    }
}
