@testable import Diagnostics
import Foundation
import SQLite3
import Testing

// MARK: - #1194 — Diagnostics.Probes read schema versions through the robust read-only open

///
/// Isolation of the bug both release reviewers converged on: the schema-version probes opened
/// with a naive `sqlite3_open_v2(READONLY)`, so a present, valid, WAL-mode database whose `-shm`
/// sidecar is absent (a locally-built corpus whose shared-memory index was evicted) read back as
/// version 0. The inventory / list_sources then reported a healthy corpus as "schema 0", which
/// the desktop reads as broken and would push the user to re-run setup. Routing the probes through
/// `SQLiteSupport.openReadOnly` (WAL `immutable=1` fallback) fixes it. This test fails on the naive
/// open and passes on the robust one.
@Suite("Diagnostics.Probes robust read-only schema probe (#1194)")
struct DiagnosticsProbesReadOnlyTests {
    /// A WAL-mode DB stamped at `userVersion`, checkpointed (so committed state is wholly in the
    /// main file), then with its `-wal`/`-shm` sidecars removed: the exact shape that read back as
    /// 0 under a naive read-only open.
    private func makeCheckpointedWALDBWithoutSidecars(userVersion: Int32) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diagprobe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("fixture.db")

        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA user_version=\(userVersion);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY); INSERT INTO t VALUES (1);", nil, nil, nil) == SQLITE_OK)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        sqlite3_close(db)
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + sidecar)
        }
        return dbURL
    }

    @Test("userVersion reads a present WAL database with no -shm sidecar, not misreported as 0")
    func readsCheckpointedWALWithoutShm() throws {
        let dbURL = try makeCheckpointedWALDBWithoutSidecars(userVersion: 18)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        #expect(Diagnostics.Probes.userVersion(at: dbURL) == 18)
    }

    @Test("userVersion returns nil for an absent database (distinct from a present unreadable one)")
    func absentDatabaseReturnsNil() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diagprobe-absent-\(UUID().uuidString).db")
        #expect(Diagnostics.Probes.userVersion(at: url) == nil)
    }

    @Test("userVersion reads a genuine version-0 rollback database as 0, not as a failure")
    func genuineZeroVersionRollbackReadsAsZero() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diagprobe-zero-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("fixture.db")

        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        // Default user_version is 0; rollback (DELETE) journal mode, no sidecars.
        #expect(sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY);", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        // A genuine version-0 DB reads as 0 (a row), not nil (a read failure).
        #expect(Diagnostics.Probes.userVersion(at: dbURL) == 0)
    }
}
