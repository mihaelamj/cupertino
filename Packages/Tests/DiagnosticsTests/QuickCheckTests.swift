@testable import Diagnostics
import Foundation
import SQLite3
import Testing

// MARK: - #1276 — Diagnostics.Probes.quickCheck surfaces an unreadable / corrupt DB

/// The bug behind discussion #1276: `cupertino setup` verified each bundled
/// database *existed* but not that it was *readable*. A truncated extract (or a
/// copy on a failing / cloud-evicted volume) opens fine and answers shallow
/// queries, then throws "disk I/O error" on the first real query at serve time.
/// `quickCheck` walks every b-tree page via `PRAGMA quick_check`, so it catches
/// that damage at setup. These tests prove a healthy DB reads `.ok` and a
/// truncated copy never does.
@Suite("Diagnostics.Probes.quickCheck (#1276)")
struct QuickCheckTests {
    /// A multi-page SQLite DB with an FTS5 index, enough rows to span many
    /// pages so a truncation reliably lops off live b-tree content.
    private func makePopulatedDB() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quickcheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("fixture.db")

        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE docs_metadata (uri TEXT PRIMARY KEY, source TEXT, title TEXT);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE VIRTUAL TABLE docs_fts USING fts5(uri, title, content);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "BEGIN;", nil, nil, nil) == SQLITE_OK)
        for index in 0..<2000 {
            let sql = """
            INSERT INTO docs_metadata VALUES ('doc://\(index)', 'swift', 'Title \(index)');
            INSERT INTO docs_fts VALUES ('doc://\(index)', 'Title \(index)', 'swift documentation body number \(index) lorem ipsum dolor sit amet');
            """
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        #expect(sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        return dbURL
    }

    @Test("a healthy populated database reports .ok")
    func healthyDatabaseIsOK() throws {
        let dbURL = try makePopulatedDB()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        #expect(Diagnostics.Probes.quickCheck(at: dbURL) == .ok)
    }

    @Test("a truncated database is never reported .ok")
    func truncatedDatabaseIsNotOK() throws {
        let dbURL = try makePopulatedDB()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let fullSize = try #require(FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? Int)
        // Lop off the back half of the file: header + early pages survive
        // (so a naive open / shallow probe still works), deep pages are gone.
        let handle = try FileHandle(forWritingTo: dbURL)
        try handle.truncate(atOffset: UInt64(fullSize / 2))
        try handle.close()

        let result = Diagnostics.Probes.quickCheck(at: dbURL)
        #expect(result != .ok, "quick_check must flag a truncated database, got \(result)")
        // Whichever way it is flagged, the carried message must be non-empty:
        // verifyExtractedDatabases renders it verbatim into the user-facing
        // "filename: <message>" failure line, so a blank message would print a
        // bare "filename: " at the CLI.
        switch result {
        case .ok:
            break
        case let .unreadable(message):
            #expect(!message.isEmpty)
        case let .problems(rows):
            #expect(!rows.isEmpty)
        }
    }

    @Test("a corrupt-but-openable database is reported .problems")
    func corruptButOpenableIsProblems() throws {
        let dbURL = try makePopulatedDB()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        // Corrupt cell content deep inside a data page (well past page 1, which
        // holds sqlite_master) while leaving the page structure parseable: the
        // file still OPENS read-only and quick_check runs to completion, but
        // reports logical inconsistencies — the "corrupt but openable" shape the
        // .problems case exists to distinguish from .unreadable. Truncation, by
        // contrast, fails at prepare and surfaces as .unreadable.
        let handle = try FileHandle(forWritingTo: dbURL)
        try handle.seek(toOffset: 8200)
        handle.write(Data(repeating: 0xff, count: 512))
        try handle.close()

        let result = Diagnostics.Probes.quickCheck(at: dbURL)
        guard case let .problems(rows) = result else {
            Issue.record("expected .problems for a corrupt-but-openable DB, got \(result)")
            return
        }
        #expect(!rows.isEmpty)
    }

    @Test("a missing file is reported .unreadable")
    func missingFileIsUnreadable() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quickcheck-missing-\(UUID().uuidString).db")

        guard case .unreadable = Diagnostics.Probes.quickCheck(at: missing) else {
            Issue.record("expected .unreadable for a missing file")
            return
        }
    }
}
