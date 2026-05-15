import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

/// Regression suite for [#607](https://github.com/mihaelamj/cupertino/issues/607).
///
/// Pre-#607, `Search.Index.indexDocument(_:)` callers that passed
/// `jsonData: nil` (the string-content strategies — `Search.Strategies.SwiftEvolution`,
/// `Search.Strategies.HIG`, `Search.Strategies.AppleArchive`) hit a nil
/// branch that hand-rolled a wrapper containing the literal
/// `"rawMarkdown":null`. The full body still reached `docs_fts.content`,
/// so `resources/read` worked, but `read_document` (MCP tool) and
/// `cupertino read` (default JSON) — both read from
/// `docs_metadata.json_data` — returned the empty wrapper to AI agents.
///
/// Post-#607 the central seam inlines `params.content` into the
/// `rawMarkdown` field of the synthesised wrapper so every nil-jsonData
/// caller, current and future, gets a complete metadata row by default.
@Suite("Search.Index nil-jsonData inlines content into rawMarkdown (#607)", .serialized)
struct IndexNilJsonDataInlinesContentTests {
    @Test("Indexing with jsonData=nil writes rawMarkdown into docs_metadata.json_data")
    func rawMarkdownPresentInWrapper() async throws {
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())

        let body = "## Heading\n\nBody with \"quotes\" and a backslash \\ plus newlines.\n"

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "swift-evolution://SE-0304",
            source: "swift-evolution",
            framework: nil,
            title: "Structured concurrency",
            content: body,
            filePath: "/tmp/SE-0304.md",
            contentHash: "deadbeef",
            lastCrawled: Date()
            // jsonData: nil (omitted) — exercises the seam under test
        ))
        await index.disconnect()

        // Read the json_data column directly. The fix should produce a
        // wrapper carrying the full markdown content under `rawMarkdown`.
        let jsonString = try Self.readJsonData(at: dbURL, source: "swift-evolution")
        let data = Data(jsonString.utf8)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Wrapper JSON did not round-trip: \(jsonString)")
            return
        }

        // The exact key the read paths look for.
        let rawMarkdown = payload["rawMarkdown"] as? String
        #expect(rawMarkdown == body, "Expected rawMarkdown to carry the original body, got: \(String(describing: rawMarkdown))")

        // Shape continuity with the pre-#607 wrapper.
        #expect(payload["title"] as? String == "Structured concurrency")
        #expect(payload["url"] as? String == "swift-evolution://SE-0304")
        #expect(payload["source"] as? String == "swift-evolution")
        #expect(payload["framework"] as? String == "")
    }

    @Test("Content with embedded backticks + control chars survives JSON round-trip")
    func difficultContentSurvives() async throws {
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())

        // Markdown bodies routinely carry fenced code, embedded quotes,
        // and tabs. JSONSerialization handles all of them; the pre-#607
        // hand-rolled string concat could not have.
        let body = """
        ```swift
        let x = "hello, \\"world\\""
        \tindented line
        ```
        """

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
        await index.disconnect()

        let jsonString = try Self.readJsonData(at: dbURL, source: "hig")
        let data = Data(jsonString.utf8)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Wrapper JSON did not round-trip on hard content: \(jsonString)")
            return
        }
        #expect(payload["rawMarkdown"] as? String == body)
    }

    @Test("Explicit jsonData parameter still wins over the nil-branch synthesis")
    func explicitJsonDataPreserved() async throws {
        // The structured-content strategies (apple-docs, swift-org,
        // swift-book) pass a real `jsonData` payload. The fix must not
        // overwrite that with the synthesised wrapper.
        let dbURL = Self.makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())

        let supplied = #"{"abstract":"Already structured","custom":"shape","rawMarkdown":"original"}"#

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://swiftui/view",
            source: "apple-docs",
            framework: "swiftui",
            title: "View",
            content: "ignored markdown body",
            filePath: "/tmp/view.json",
            contentHash: "cafebabe",
            lastCrawled: Date(),
            jsonData: supplied
        ))
        await index.disconnect()

        let stored = try Self.readJsonData(at: dbURL, source: "apple-docs")
        #expect(stored == supplied, "Explicit jsonData should pass through verbatim, got: \(stored)")
    }

    // MARK: - Helpers

    private static func makeTempDB() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "search-#607-\(UUID().uuidString).db"
        )
    }

    /// Read the `json_data` column of the first row in `docs_metadata`
    /// whose `source` matches. Direct sqlite3 read so the test doesn't
    /// rely on any Search.Index method that itself touches `json_data`.
    private static func readJsonData(at dbURL: URL, source: String) throws -> String {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "open(\(dbURL.path)) failed",
            ])
        }
        let sql = "SELECT json_data FROM docs_metadata WHERE source = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "prepare failed: \(String(cString: sqlite3_errmsg(db)))",
            ])
        }
        sqlite3_bind_text(stmt, 1, (source as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cString = sqlite3_column_text(stmt, 0) else {
            throw NSError(domain: "TestSetup", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "no docs_metadata row for source=\(source)",
            ])
        }
        return String(cString: cString)
    }
}
