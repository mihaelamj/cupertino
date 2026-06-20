import Foundation
@testable import ReleaseTool
import SQLite3
import Testing

// MARK: - Release.Publishing.convertToRollbackJournal (#1192)

// Verifies the release-time journal-mode conversion that runs (after the
// #236 checkpoint) before `Release.Command.Database` zips each DB. The
// indexer builds DBs in WAL mode, and a WAL DB cannot be opened read-only
// without an accompanying `-shm` shared-memory index, so a freshly-extracted
// WAL DB (no sidecar) fails every plain `SQLITE_OPEN_READONLY` open. Shipping
// the artifact in rollback (DELETE) mode removes that requirement, so every
// read-only open works uniformly. This is a header/mode flip only; content is
// untouched.

@Suite("Release.Publishing.convertToRollbackJournal (#1192)")
struct ConvertToRollbackJournalTests {
    enum TestError: Error { case openFailed }

    @Test("converts WAL to rollback so the DB opens read-only with no -shm")
    func convertsWALToRollback() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rel-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("packages.db")

        try buildWALDatabase(at: dbURL)
        // Header says WAL (write/read version bytes both 2) before conversion.
        #expect(try headerJournalBytes(at: dbURL) == (2, 2))

        // Fresh-extract shape: only the main file, no shared-memory index.
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + sidecar)
        }

        // Pre-condition (the bug): a WAL DB with no -shm cannot be queried read-only.
        #expect(!canQueryReadOnly(at: dbURL))

        // Convert in place.
        let mode = try Release.Publishing.convertToRollbackJournal(at: dbURL)
        #expect(mode == "delete")

        // Header is now rollback (write/read version bytes both 1), sidecars gone.
        #expect(try headerJournalBytes(at: dbURL) == (1, 1))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-shm"))

        // Post-condition (the fix): plain read-only query succeeds, still no -shm.
        #expect(canQueryReadOnly(at: dbURL))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-shm"))
    }

    /// End-to-end guard (#1254 item 2): every database the release ships must end
    /// in rollback journal mode and open read-only with no `-shm`. This runs the
    /// exact two release-prep steps `Release.Command.Database.run()` applies
    /// (`checkpointTruncate` then `convertToRollbackJournal`) over the FULL
    /// registry-derived bundle set (`bundledDescriptors()`), not a single DB — so
    /// a source added to the registry is covered automatically, and a regression
    /// that shipped any bundled DB in WAL mode (the #1254-item-2 failure: a
    /// freshly-extracted WAL DB with no `-shm` fails every read-only open) is
    /// caught here rather than in a shipped bundle. The conversion + the zip use
    /// the same `present` list in `run()`, so "every converted DB is bundled" holds
    /// by construction; this pins "every bundled DB converts cleanly".
    @Test("every bundled DB (full registry set) ships rollback + opens read-only with no -shm")
    func everyBundledDatabaseShipsRollback() throws {
        let descriptors = Release.Command.Database.bundledDescriptors()
        // The bundle is the canonical per-source set (8 today); the loop covers
        // whatever the registry declares, so a new source is guarded automatically.
        #expect(descriptors.count >= 8, "expected at least the canonical 8 per-source DBs, got \(descriptors.count)")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rel-bundle-1254-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for descriptor in descriptors {
            let dbURL = dir.appendingPathComponent(descriptor.filename)
            // Indexer shape: a WAL-mode DB (the close-time checkpoint may fold the
            // WAL, so the prep's checkpoint is exercised either way).
            try buildWALDatabase(at: dbURL)

            // The exact release-prep sequence from Release.Command.Database.run().
            _ = try Release.Publishing.checkpointTruncate(at: dbURL)
            let mode = try Release.Publishing.convertToRollbackJournal(at: dbURL)

            #expect(mode == "delete", "\(descriptor.filename) is not rollback after release prep")
            #expect(try headerJournalBytes(at: dbURL) == (1, 1), "\(descriptor.filename) header is not rollback mode")
            #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-wal"), "\(descriptor.filename) still has a -wal sidecar")
            #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-shm"), "\(descriptor.filename) still has a -shm sidecar")
            // The shipped artifact must be queryable through a plain read-only open
            // (no -shm), and the read must not create one.
            #expect(canQueryReadOnly(at: dbURL), "\(descriptor.filename) cannot be queried read-only with no -shm")
            #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-shm"), "\(descriptor.filename) read-only query created a -shm")
        }
    }

    // MARK: - Fixture helpers

    /// Build a WAL-mode DB with a little data and close it (the close-time
    /// checkpoint folds the WAL into the main file in a single-process test).
    private func buildWALDatabase(at path: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path.path, &db) == SQLITE_OK else { throw TestError.openFailed }
        _ = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        _ = sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, payload BLOB);", nil, nil, nil)
        _ = sqlite3_exec(db, "BEGIN;", nil, nil, nil)
        let blob = String(repeating: "x", count: 4096)
        for row in 0..<32 {
            _ = sqlite3_exec(db, "INSERT INTO t VALUES (\(row), '\(blob)');", nil, nil, nil)
        }
        _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        sqlite3_close(db)
    }

    /// Read the SQLite header's write/read journal-version bytes (offsets 18
    /// and 19): both 2 means WAL, both 1 means a rollback journal mode.
    private func headerJournalBytes(at url: URL) throws -> (UInt8, UInt8) {
        let data = try Data(contentsOf: url)
        return (data[18], data[19])
    }

    /// Whether the DB can be both opened AND queried through a plain
    /// `SQLITE_OPEN_READONLY` connection. (The open is lazy, so the WAL-no-shm
    /// failure only surfaces when the first statement runs.)
    private func canQueryReadOnly(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM t;", -1, &stmt, nil) == SQLITE_OK else { return false }
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
