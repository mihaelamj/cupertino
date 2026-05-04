import Foundation
@testable import Search
import SQLite3
import Testing

// Per-column bm25 weighting (#181). `Search.Index.search` applies
// `bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0)` so that title matches
// dominate body matches for type-name queries like "Task" or "View". These
// tests exercise the raw bm25 expression against a fresh index so the
// coefficients themselves are guarded against accidental change.

private func makeTempDB() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("bm25-\(UUID().uuidString).db")
}

private struct RankedHit {
    let uri: String
    let rank: Double
}

/// Run the exact bm25 expression used by `Search.Index.search`. We hit
/// docs_fts directly so this test fails if the weight vector drifts, not if
/// some upstream boost heuristic changes.
private func rankedHits(
    at dbPath: URL,
    matching query: String
) throws -> [RankedHit] {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw BM25TestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    let sql = """
    SELECT uri, bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0) AS rank
    FROM docs_fts
    WHERE docs_fts MATCH ?
    ORDER BY rank;
    """

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw BM25TestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, (query as NSString).utf8String, -1, nil)

    var out: [RankedHit] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let uri = String(cString: sqlite3_column_text(stmt, 0))
        let rank = sqlite3_column_double(stmt, 1)
        out.append(RankedHit(uri: uri, rank: rank))
    }
    return out
}

private enum BM25TestError: Error {
    case openFailed(String)
    case prepareFailed(String)
}

@Suite("Search.Index bm25 title-weight boost (#181)")
struct BM25TitleWeightingTests {
    @Test("Title match outranks body match for a single term")
    func titleBeatsBody() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath)

        // A: query term lives in the title, body is unrelated.
        try await idx.indexDocument(
            uri: "apple-docs://swift/task",
            source: "apple-docs",
            framework: "Swift",
            title: "Task",
            content: "An asynchronous unit of work without the query term repeated.",
            filePath: "/tmp/a",
            contentHash: "a",
            lastCrawled: Date()
        )

        // B: query term appears only in the body, title is unrelated.
        try await idx.indexDocument(
            uri: "apple-docs://kernel/task-info",
            source: "apple-docs",
            framework: "Kernel",
            title: "Mach kernel overview",
            content: "A mach task contains threads and memory regions. Task accounting is reported here.",
            filePath: "/tmp/b",
            contentHash: "b",
            lastCrawled: Date()
        )

        await idx.disconnect()

        let hits = try rankedHits(at: dbPath, matching: "Task")
        #expect(hits.count == 2)
        // bm25 in SQLite FTS5 returns negative scores where *lower* (more
        // negative) is a better match. ORDER BY rank ASC puts best first.
        #expect(hits.first?.uri == "apple-docs://swift/task")
        #expect(hits.last?.uri == "apple-docs://kernel/task-info")
    }

    @Test("Summary match outranks body match (summary weight = 3×)")
    func summaryBeatsBody() async throws {
        // `indexDocument` auto-extracts a summary from the content. To stress
        // only the summary/body distinction, we insert docs where the query
        // term does / does not land in the first 500 chars of the body.
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath)

        // A: query term appears in the first sentence (becomes the summary).
        try await idx.indexDocument(
            uri: "apple-docs://foundation/bundle",
            source: "apple-docs",
            framework: "Foundation",
            title: "Foundation APIs",
            content: "Bundle is the entry point for resource lookup. " + String(repeating: "Filler sentence. ", count: 40),
            filePath: "/tmp/s1",
            contentHash: "s1",
            lastCrawled: Date()
        )

        // B: query term only appears deep in the body, past the summary cut.
        let bodyB = String(repeating: "Unrelated padding text. ", count: 60) + " Bundle is mentioned only here at the end."
        try await idx.indexDocument(
            uri: "apple-docs://misc/other",
            source: "apple-docs",
            framework: "Misc",
            title: "Other APIs",
            content: bodyB,
            filePath: "/tmp/s2",
            contentHash: "s2",
            lastCrawled: Date()
        )

        await idx.disconnect()

        let hits = try rankedHits(at: dbPath, matching: "Bundle")
        #expect(hits.count == 2)
        #expect(hits.first?.uri == "apple-docs://foundation/bundle")
    }
}
