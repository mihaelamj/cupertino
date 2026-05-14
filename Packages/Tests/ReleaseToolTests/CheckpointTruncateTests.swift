import Foundation
@testable import ReleaseTool
import SQLite3
import Testing

// MARK: - Release.Publishing.checkpointTruncate (#236)

// Verifies the release-time WAL checkpoint helper that runs before
// `Release.Command.Database` zips the three cupertino DBs for the
// GitHub Release artifact. Without it, a `.db` file in the zip
// could be missing pages that are still trapped in a `.db-wal`
// sidecar at zip time — `cupertino setup` users would silently
// search a stale corpus.

@Suite("Release.Publishing.checkpointTruncate (#236)")
struct CheckpointTruncateTests {
    @Test("Runs cleanly against a WAL-mode DB and leaves no WAL sidecar")
    func checkpointTruncateLeavesNoSidecar() throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("rel-checkpoint-\(UUID().uuidString).db")
        let walURL = URL(fileURLWithPath: tempDB.path + "-wal")
        let shmURL = URL(fileURLWithPath: tempDB.path + "-shm")
        defer {
            try? FileManager.default.removeItem(at: tempDB)
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
        }

        // Build a real WAL DB with data and let SQLite close it
        // normally. SQLite's close-time checkpoint already folds
        // everything in the WAL back into the main file in a
        // single-process test scenario — there's no easy way to
        // simulate a "dirty WAL at close" without process isolation
        // (because the last connection's `sqlite3_close` always
        // runs a final checkpoint). So this test verifies the
        // post-condition: the helper runs cleanly, returns a sane
        // outcome, and the `.db-wal` sidecar is gone afterward.
        // The fold-frames behavior is exercised in real-world
        // release-tool runs against a freshly-built bundle DB.
        try buildWALDatabase(at: tempDB)

        let outcome = try Release.Publishing.checkpointTruncate(at: tempDB)
        #expect(!outcome.busy, "No concurrent connections — TRUNCATE should not return SQLITE_BUSY")

        // Post-condition: WAL sidecar gone (or zero bytes).
        let postExists = FileManager.default.fileExists(atPath: walURL.path)
        if postExists {
            let postSize = (try? FileManager.default.attributesOfItem(atPath: walURL.path)[.size] as? Int64) ?? -1
            #expect(postSize == 0, "WAL sidecar should be truncated to 0 bytes (got \(postSize))")
        }
    }

    @Test("Idempotent on an already-clean WAL DB (second call still ok)")
    func checkpointTruncateIsIdempotent() throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("rel-checkpoint-idem-\(UUID().uuidString).db")
        defer {
            try? FileManager.default.removeItem(at: tempDB)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempDB.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempDB.path + "-shm"))
        }

        try buildWALDatabase(at: tempDB)
        _ = try Release.Publishing.checkpointTruncate(at: tempDB)
        let outcome = try Release.Publishing.checkpointTruncate(at: tempDB)
        #expect(outcome.walSizeAfter == 0)
        #expect(!outcome.busy)
    }

    @Test("Surfaces openFailed for a path under a missing directory")
    func checkpointTruncateMissingFileFails() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("rel-checkpoint-missing-\(UUID().uuidString)")
            .appendingPathComponent("nope.db")
        // Parent directory doesn't exist, so sqlite3_open's
        // create-on-open fails.
        #expect(throws: Release.Publishing.CheckpointError.self) {
            _ = try Release.Publishing.checkpointTruncate(at: missing)
        }
    }

    // MARK: - Helpers

    /// Build a fresh SQLite database in WAL mode with a bit of data
    /// and close cleanly. Used by tests above to verify the helper
    /// runs without error on real WAL files. Single-process Swift
    /// tests can't easily leave a "dirty" WAL because SQLite's
    /// close-time checkpoint always drains the sidecar; the helper's
    /// behavior on dirty WALs is covered by real release-tool runs.
    private func buildWALDatabase(at path: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path.path, &db) == SQLITE_OK else {
            throw CheckpointTestError.openFailed
        }
        _ = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        _ = sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, payload BLOB);", nil, nil, nil)
        _ = sqlite3_exec(db, "BEGIN;", nil, nil, nil)
        let blob = String(repeating: "x", count: 4096)
        for i in 0..<32 {
            _ = sqlite3_exec(db, "INSERT INTO t VALUES (\(i), '\(blob)');", nil, nil, nil)
        }
        _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        sqlite3_close(db)
    }

    private enum CheckpointTestError: Error {
        case openFailed
    }
}
