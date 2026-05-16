@testable import Diagnostics
import Foundation
import SQLite3
import Testing

// MARK: - #626 — Diagnostics.Probes.kindHistogramBySource

//
// Powers the new `cupertino doctor --kind-coverage` flag. The probe
// joins `docs_metadata` (carries `source`) with `docs_structured`
// (carries `kind` from schema v11) and groups by `(source, kind)`.
// Rows with no docs_structured entry render as `(missing)` so they
// stay distinguishable from rows tagged `unknown` by the kind
// extractor.

@Suite("#626 Diagnostics.Probes.kindHistogramBySource")
struct KindHistogramBySourceTests {
    /// Build a stub search.db at `dbPath` with the minimal schema the
    /// probe needs (`docs_metadata` + `docs_structured`) and seed it
    /// with the given rows. Bypasses the full `Search.Index` so the
    /// test is fast and doesn't drag in WAL / FTS setup.
    private func seed(
        at dbPath: URL,
        rows: [(uri: String, source: String, kind: String?)]
    ) throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "open failed"])
        }
        defer { sqlite3_close(db) }

        let createMeta = """
        CREATE TABLE docs_metadata (
            uri TEXT PRIMARY KEY,
            source TEXT NOT NULL
        );
        """
        let createStructured = """
        CREATE TABLE docs_structured (
            uri TEXT PRIMARY KEY,
            kind TEXT
        );
        """
        guard sqlite3_exec(db, createMeta, nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(db, createStructured, nil, nil, nil) == SQLITE_OK
        else {
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "create failed: \(String(cString: sqlite3_errmsg(db)))"])
        }

        for row in rows {
            let metaSQL = "INSERT INTO docs_metadata (uri, source) VALUES (?, ?);"
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, metaSQL, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, (row.uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (row.source as NSString).utf8String, -1, nil)
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)

            if let kind = row.kind {
                let structSQL = "INSERT INTO docs_structured (uri, kind) VALUES (?, ?);"
                var stmt2: OpaquePointer?
                sqlite3_prepare_v2(db, structSQL, -1, &stmt2, nil)
                sqlite3_bind_text(stmt2, 1, (row.uri as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt2, 2, (kind as NSString).utf8String, -1, nil)
                _ = sqlite3_step(stmt2)
                sqlite3_finalize(stmt2)
            }
        }
    }

    @Test("Groups by (source, kind) and orders by source asc, count desc")
    func happyPath() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-626-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        try seed(at: dbPath, rows: [
            ("apple-docs://swiftui/view", "apple-docs", "class"),
            ("apple-docs://swiftui/text", "apple-docs", "class"),
            ("apple-docs://swiftui/color", "apple-docs", "struct"),
            ("apple-docs://uikit/uibutton", "apple-docs", "unknown"),
            ("samples://hello", "samples", "sampleCode"),
        ])

        let result = try #require(Diagnostics.Probes.kindHistogramBySource(at: dbPath))

        // Source order is `apple-docs` first, `samples` second
        // (alphabetic asc). Within `apple-docs`, `class` (2) leads
        // `struct` (1) and `unknown` (1) ties on count but sorts
        // alphabetically as a SQLite secondary key.
        let appleDocs = result.filter { $0.source == "apple-docs" }
        #expect(appleDocs.count == 3)
        #expect(appleDocs.first?.kind == "class")
        #expect(appleDocs.first?.count == 2)

        let samples = result.filter { $0.source == "samples" }
        #expect(samples.count == 1)
        #expect(samples.first?.kind == "sampleCode")
    }

    @Test("Rows with no docs_structured entry surface as (missing)")
    func missingStructuredRendersAsMissing() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-626-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        try seed(at: dbPath, rows: [
            ("apple-archive://articles/intro", "apple-archive", nil),
            ("apple-archive://articles/setup", "apple-archive", nil),
            ("apple-archive://articles/uses-kind", "apple-archive", "article"),
        ])

        let result = try #require(Diagnostics.Probes.kindHistogramBySource(at: dbPath))

        let missingEntry = result.first { $0.kind == "(missing)" && $0.source == "apple-archive" }
        let articleEntry = result.first { $0.kind == "article" && $0.source == "apple-archive" }
        #expect(missingEntry?.count == 2)
        #expect(articleEntry?.count == 1)
    }

    @Test("Returns nil on missing DB file (caller renders as skipped)")
    func missingDB() {
        let url = URL(fileURLWithPath: "/tmp/cupertino-nonexistent-626-\(UUID().uuidString).db")
        #expect(Diagnostics.Probes.kindHistogramBySource(at: url) == nil)
    }

    @Test("Returns empty array (not nil) when DB exists with valid schema but zero rows")
    func emptyButValidDB() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-626-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        try seed(at: dbPath, rows: [])

        let result = Diagnostics.Probes.kindHistogramBySource(at: dbPath)
        #expect(result != nil)
        #expect(result?.isEmpty == true)
    }
}
