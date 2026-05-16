@testable import CLI
import Foundation
import SQLite3
import Testing

// MARK: - #673 Phase G — sidecar atomic-replace + orphan cleanup

//
// `CLIImpl.Command.Save.cleanUpOrphanSidecar(at:)` + `.atomicReplaceWithSidecar(actual:sidecar:)`
// are the two file-system primitives that make `cupertino save --clear`
// crash-safe. A `kill -9` mid-save now leaves the original DB at the
// actual path intact because writes never touch it — they go to a
// `<actual>.in-flight` sidecar, and only an atomic rename on
// successful save promotes the sidecar into place.
//
// These tests live in SearchTests because the CLI target's static
// helpers are accessible there via the test bundle; they exercise the
// pure file-system behaviour without needing to spin up a full
// `cupertino save` process. The end-to-end "kill -9 mid-save"
// scenario is covered by manual + CI smoke tests in PR #696's body.

@Suite("#673 Phase G — sidecar atomic-replace + orphan cleanup", .serialized)
struct Issue673PhaseGSidecarTests {
    // MARK: - Helpers

    /// Create a SQLite file with a known marker row so we can verify
    /// the original survives across the test (or doesn't, when we
    /// expect the replace to take effect).
    private func makeMarkedDB(at url: URL, marker: String) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(db) }
        try #require(sqlite3_exec(db, "CREATE TABLE markers (v TEXT);", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(db, "INSERT INTO markers VALUES ('\(marker)');", nil, nil, nil) == SQLITE_OK)
    }

    /// Read the marker back from the SQLite file.
    private func readMarker(from url: URL) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close_v2(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT v FROM markers LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-673-phase-g-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - atomicReplaceWithSidecar — the rename half

    @Test("atomicReplaceWithSidecar replaces an existing DB with the sidecar's contents")
    func atomicReplaceSwapsContent() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let actual = dir.appendingPathComponent("search.db")
        let sidecar = actual.appendingPathExtension("in-flight")

        try makeMarkedDB(at: actual, marker: "OLD")
        try makeMarkedDB(at: sidecar, marker: "NEW")

        try CLIImpl.Command.Save.atomicReplaceWithSidecar(actual: actual, sidecar: sidecar)

        // After the replace, `actual` should carry the NEW marker (the
        // sidecar's content). The sidecar should no longer exist at its
        // original path (it was renamed into `actual`'s place).
        #expect(readMarker(from: actual) == "NEW", "actual DB should carry sidecar's content after replace")
        #expect(FileManager.default.fileExists(atPath: sidecar.path) == false, "sidecar should be consumed by replace")
    }

    @Test("atomicReplaceWithSidecar handles the no-existing-DB case (move-in-place)")
    func atomicReplaceMovesInPlaceWhenNoActual() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let actual = dir.appendingPathComponent("search.db")
        let sidecar = actual.appendingPathExtension("in-flight")

        // Only the sidecar exists; the actual path is empty (first save scenario).
        try makeMarkedDB(at: sidecar, marker: "FIRST")
        #expect(FileManager.default.fileExists(atPath: actual.path) == false, "actual should not pre-exist")

        try CLIImpl.Command.Save.atomicReplaceWithSidecar(actual: actual, sidecar: sidecar)

        #expect(readMarker(from: actual) == "FIRST", "first-save sidecar should be moved in place")
        #expect(FileManager.default.fileExists(atPath: sidecar.path) == false, "sidecar should be consumed")
    }

    @Test("atomicReplaceWithSidecar cleans up stale WAL/SHM/journal companions at the target")
    func atomicReplaceClearsStaleCompanions() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let actual = dir.appendingPathComponent("search.db")
        let sidecar = actual.appendingPathExtension("in-flight")

        try makeMarkedDB(at: actual, marker: "OLD")
        try makeMarkedDB(at: sidecar, marker: "NEW")

        // Simulate stale WAL + SHM from a prior in-place save crash.
        let staleWAL = URL(fileURLWithPath: actual.path + "-wal")
        let staleSHM = URL(fileURLWithPath: actual.path + "-shm")
        try Data("stale".utf8).write(to: staleWAL)
        try Data("stale".utf8).write(to: staleSHM)

        try CLIImpl.Command.Save.atomicReplaceWithSidecar(actual: actual, sidecar: sidecar)

        #expect(FileManager.default.fileExists(atPath: staleWAL.path) == false, "stale WAL should be removed before replace")
        #expect(FileManager.default.fileExists(atPath: staleSHM.path) == false, "stale SHM should be removed before replace")
        #expect(readMarker(from: actual) == "NEW", "actual should still get the sidecar's content")
    }

    // MARK: - cleanUpOrphanSidecar — the start-of-save half

    @Test("cleanUpOrphanSidecar removes a leftover .in-flight from a prior crashed save")
    func orphanSidecarIsRemoved() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let actual = dir.appendingPathComponent("search.db")
        let orphan = actual.appendingPathExtension("in-flight")

        try makeMarkedDB(at: actual, marker: "ORIGINAL")
        try makeMarkedDB(at: orphan, marker: "ORPHANED")

        CLIImpl.Command.Save.cleanUpOrphanSidecar(at: orphan)

        #expect(FileManager.default.fileExists(atPath: orphan.path) == false, "orphan sidecar should be removed")
        // Critical: original DB at the actual path must NOT be touched.
        #expect(readMarker(from: actual) == "ORIGINAL", "original DB at actual path must survive orphan cleanup")
    }

    @Test("cleanUpOrphanSidecar is a no-op when no sidecar exists (idempotent)")
    func orphanSidecarNoOpWhenAbsent() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let actual = dir.appendingPathComponent("search.db")
        try makeMarkedDB(at: actual, marker: "ONLY")
        let sidecar = actual.appendingPathExtension("in-flight")
        #expect(FileManager.default.fileExists(atPath: sidecar.path) == false)

        // Should not throw, should not touch the actual DB.
        CLIImpl.Command.Save.cleanUpOrphanSidecar(at: sidecar)

        #expect(readMarker(from: actual) == "ONLY", "no-op cleanup must not touch the actual DB")
    }

    @Test("cleanUpOrphanSidecar removes the sidecar's WAL/SHM companions too")
    func orphanSidecarRemovesCompanions() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let actual = dir.appendingPathComponent("search.db")
        let orphan = actual.appendingPathExtension("in-flight")
        try makeMarkedDB(at: actual, marker: "ORIGINAL")
        try makeMarkedDB(at: orphan, marker: "ORPHANED")

        // Simulate orphaned WAL + SHM next to the in-flight DB.
        let orphanWAL = URL(fileURLWithPath: orphan.path + "-wal")
        let orphanSHM = URL(fileURLWithPath: orphan.path + "-shm")
        try Data("stale".utf8).write(to: orphanWAL)
        try Data("stale".utf8).write(to: orphanSHM)

        CLIImpl.Command.Save.cleanUpOrphanSidecar(at: orphan)

        #expect(FileManager.default.fileExists(atPath: orphan.path) == false)
        #expect(FileManager.default.fileExists(atPath: orphanWAL.path) == false, "sidecar WAL should be removed")
        #expect(FileManager.default.fileExists(atPath: orphanSHM.path) == false, "sidecar SHM should be removed")
        // Original always survives.
        #expect(readMarker(from: actual) == "ORIGINAL")
    }
}
