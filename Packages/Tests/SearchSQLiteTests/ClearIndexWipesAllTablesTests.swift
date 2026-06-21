import Foundation
import LoggingModels
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// 2026-06-21: clearIndex() (the `save --clear` / full-rebuild path)
// deleted only `docs_fts` + `docs_metadata`, leaving `docs_structured`
// and the other rich-data tables fully populated. The
// `ON DELETE CASCADE` from docs_structured → docs_metadata never fired
// because PRAGMA foreign_keys is off on the indexer connection, so a
// re-crawl + `save --clear` of hig.db kept its 173 placeholder-duplicate
// rows in docs_structured. This test pins the invariant: clearIndex
// empties EVERY docs-schema table, not just the FTS.
@Suite("clearIndex wipes all docs tables")
struct ClearIndexWipesAllTablesTests {
    @MainActor
    private static func makeIndex() async throws -> (Search.Index, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearindex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbPath = tmp.appendingPathComponent("test.db")
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        return (index, dbPath)
    }

    /// Open a short-lived raw connection to the same file, run `body`, close.
    private static func withRawDB<T>(_ path: URL, _ body: (OpaquePointer) -> T) -> T {
        var db: OpaquePointer?
        _ = sqlite3_open(path.path, &db)
        defer { sqlite3_close(db) }
        return body(db!)
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private static func count(_ db: OpaquePointer, _ table: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table);", -1, &stmt, nil) == SQLITE_OK
        else { return -1 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    @Test("clearIndex empties docs_structured, not just the FTS")
    @MainActor
    func clearIndexWipesStructured() async throws {
        let (index, dbPath) = try await Self.makeIndex()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        // Seed one document across the rich-data + FTS tables, the shape a
        // real save produces.
        Self.withRawDB(dbPath) { db in
            Self.exec(db, """
            INSERT INTO docs_metadata (uri, framework, file_path, content_hash, last_crawled, word_count)
            VALUES ('hig://components/buttons', 'hig', '/x', 'h', 0, 1);
            INSERT INTO docs_structured (uri, url, title)
            VALUES ('hig://components/buttons', 'https://example/x', 'Buttons');
            INSERT INTO docs_fts (uri, title, content)
            VALUES ('hig://components/buttons', 'Buttons', 'body text');
            """)
        }
        Self.withRawDB(dbPath) { db in
            #expect(Self.count(db, "docs_metadata") == 1)
            #expect(Self.count(db, "docs_structured") == 1)
            #expect(Self.count(db, "docs_fts") == 1)
        }

        try await index.clearIndex()

        // The regression: before the fix, docs_structured stayed at 1
        // because only docs_fts + docs_metadata were deleted.
        Self.withRawDB(dbPath) { db in
            #expect(Self.count(db, "docs_metadata") == 0)
            #expect(Self.count(db, "docs_structured") == 0, "docs_structured must be wiped by clearIndex")
            #expect(Self.count(db, "docs_fts") == 0)
        }
    }
}
