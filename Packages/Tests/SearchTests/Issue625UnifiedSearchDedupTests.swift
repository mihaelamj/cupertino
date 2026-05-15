import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

/// Regression suite for [#625](https://github.com/mihaelamj/cupertino/issues/625).
///
/// `cupertino search <type>` **without** `--source` runs the
/// cross-source aggregator (`Search.SmartQuery.answer`) which fuses
/// per-fetcher batches via reciprocal rank fusion. RRF sums increments
/// per `source\u{1F}identifier` key; pre-fix, when `docs_fts` carried
/// multiple rows for the same `uri` (the shipped v1.1.0 bundle had
/// e.g. 3 rows for `apple-docs://naturallanguage/string` while
/// `docs_metadata` had 1 — a corpus-level dup the indexer didn't dedupe
/// pre-#587), the JOIN returned all 3 to `Search.Index.search`, the
/// `DocsSourceCandidateFetcher` passed them through verbatim, and RRF
/// summed 3 contributions to the same fused key. Inflated score
/// pushed the page above legitimately-ranked canonicals.
///
/// Fix: `Search.Index.search` now skips repeat `uri`s after the first
/// (best-BM25-rank) occurrence. The dedup runs in Swift after the SQL
/// (cheaper than `GROUP BY` over the full result-set columns + window
/// functions) and is robust to whatever shape the FTS row-count
/// happens to be in.
@Suite("#625 cross-source aggregator dedup", .serialized)
struct Issue625UnifiedSearchDedupTests {
    @Test("Search.Index.search returns each uri at most once even when docs_fts has duplicate rows for one uri")
    func searchDedupesDuplicateFTSRows() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue625-dedup-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())

        // Seed one row through the normal indexer path.
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://demo/string",
            source: "apple-docs",
            framework: "demo",
            title: "string",
            content: "Demo string utility — String is the test fixture term here.",
            filePath: "/tmp/demo.md",
            contentHash: UUID().uuidString,
            lastCrawled: Date()
        ))
        // Inject two MORE docs_fts rows for the same uri to simulate
        // the v1.1.0 corpus shape that produced #625's inflated score.
        // docs_metadata still has 1 row (the indexer didn't write more).
        await index.disconnect()
        try Self.injectDuplicateFTSRows(at: dbURL, uri: "apple-docs://demo/string", extraCount: 2)

        // Add a competing legitimate row so the "wrong winner" condition
        // could trigger — pre-fix the duplicate fixture would sum 3 RRF
        // increments and outrank this one.
        let index2 = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
        try await index2.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://swift/string",
            source: "apple-docs",
            framework: "swift",
            title: "String | Apple Developer Documentation",
            content: "A Unicode string value that is a collection of characters.",
            filePath: "/tmp/swift-string.md",
            contentHash: UUID().uuidString,
            lastCrawled: Date(),
            jsonData: #"{"title":"String","kind":"struct","rawMarkdown":"...","source":"apple-docs","framework":"swift","abstract":"A Unicode string value."}"#
        ))

        // The search must return the demo URI exactly once.
        let rows = try await index2.search(query: "String", source: "apple-docs", limit: 20)
        await index2.disconnect()

        let demoCount = rows.filter { $0.uri == "apple-docs://demo/string" }.count
        #expect(demoCount == 1, "Search.Index.search must deduplicate by uri; got \(demoCount) rows for apple-docs://demo/string")

        // The canonical swift/string is still present (dedup didn't drop it).
        #expect(rows.contains { $0.uri == "apple-docs://swift/string" })
    }

    @Test("Multiple distinct URIs each appear exactly once (sanity)")
    func multipleURIsEachOnce() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue625-multi-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
        for i in 1...5 {
            try await index.indexDocument(Search.Index.IndexDocumentParams(
                uri: "apple-docs://demo/x\(i)",
                source: "apple-docs",
                framework: "demo",
                title: "X\(i)",
                content: "Demo string content number \(i).",
                filePath: "/tmp/x\(i).md",
                contentHash: UUID().uuidString,
                lastCrawled: Date()
            ))
        }

        let rows = try await index.search(query: "string", source: "apple-docs", limit: 20)
        await index.disconnect()

        let uris = rows.map(\.uri)
        let uniqueURIs = Set(uris)
        #expect(uris.count == uniqueURIs.count, "every uri should appear at most once; got duplicates in \(uris)")
    }

    // MARK: - Helper

    /// Add `extraCount` additional `docs_fts` rows for `uri`, copying the
    /// content of the existing row. Mimics the shipped-bundle dup the fix
    /// is defending against.
    private static func injectDuplicateFTSRows(at dbURL: URL, uri: String, extraCount: Int) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "open(\(dbURL.path)) failed",
            ])
        }
        let sql = """
        INSERT INTO docs_fts (uri, source, framework, language, title, content, summary, symbols)
        SELECT uri, source, framework, language, title, content, summary, symbols
        FROM docs_fts WHERE uri = ?;
        """
        for _ in 0..<extraCount {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(
                    domain: "TestSetup", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
                )
            }
            sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw NSError(
                    domain: "TestSetup", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
                )
            }
        }
    }
}
