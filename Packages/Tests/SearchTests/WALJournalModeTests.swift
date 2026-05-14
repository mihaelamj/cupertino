import Diagnostics
import Foundation
import SampleIndex
import SampleIndexModels
@testable import Search
import SearchModels
import SharedConstants
import Testing

// MARK: - WAL Journal Mode Tests (#236)

// Verifies that every local SQLite database `cupertino` opens for
// writes is switched to WAL journal mode. WAL lets `cupertino search`
// / `ask` / `doctor` proceed while a `cupertino save` writer holds
// the database; the default rollback journal blocks them.
//
// The acceptance criteria from #236 boil down to:
//
//   1. A fresh init leaves the DB in `wal` mode.
//   2. Re-init on an already-WAL DB is a no-op (PRAGMA is idempotent).
//   3. `Diagnostics.Probes.journalMode(at:)` reports `"wal"` for each.

@Suite("WAL journal mode (#236)")
struct WALJournalModeTests {
    @Test("Search.Index opens search.db in WAL mode")
    func searchIndexEnablesWAL() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-search-\(UUID().uuidString).db")
        defer {
            try? FileManager.default.removeItem(at: tempDB)
            try? FileManager.default.removeItem(at: tempDB.appendingPathExtension("wal-wal"))
            try? FileManager.default.removeItem(at: tempDB.appendingPathExtension("wal-shm"))
        }

        let index = try await Search.Index(dbPath: tempDB)
        await index.disconnect()

        let mode = Diagnostics.Probes.journalMode(at: tempDB)
        #expect(mode == "wal", "search.db should be in WAL mode after init")
    }

    @Test("Search.PackageIndex opens packages.db in WAL mode")
    func packageIndexEnablesWAL() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-packages-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let index = try await Search.PackageIndex(dbPath: tempDB)
        await index.disconnect()

        let mode = Diagnostics.Probes.journalMode(at: tempDB)
        #expect(mode == "wal", "packages.db should be in WAL mode after init")
    }

    @Test("Sample.Index.Database opens samples.db in WAL mode")
    func sampleIndexEnablesWAL() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-samples-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let database = try await Sample.Index.Database(dbPath: tempDB)
        await database.disconnect()

        let mode = Diagnostics.Probes.journalMode(at: tempDB)
        #expect(mode == "wal", "samples.db should be in WAL mode after init")
    }

    @Test("Re-opening an already-WAL search.db stays in WAL (idempotent PRAGMA)")
    func searchIndexReopenIsIdempotent() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-reopen-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        // First init switches the journal to WAL.
        let first = try await Search.Index(dbPath: tempDB)
        await first.disconnect()
        #expect(Diagnostics.Probes.journalMode(at: tempDB) == "wal")

        // Second init on the same file should leave the mode unchanged.
        // The PRAGMA is idempotent and persists in the file header, so
        // re-running it on a WAL file is a no-op.
        let second = try await Search.Index(dbPath: tempDB)
        await second.disconnect()
        #expect(Diagnostics.Probes.journalMode(at: tempDB) == "wal")
    }

    @Test("Search.Index sets synchronous=NORMAL on its own connection")
    func searchIndexSetsSynchronousNormal() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-sync-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let index = try await Search.Index(dbPath: tempDB)
        let mode = await index.currentSynchronousMode()
        await index.disconnect()

        // SQLite enum: 0=OFF, 1=NORMAL, 2=FULL, 3=EXTRA. The default
        // is FULL (2); the #236 follow-up flips writers to NORMAL (1).
        #expect(mode == 1, "Search.Index should set synchronous=NORMAL on its own connection (got \(mode ?? -1))")
    }

    @Test("Search.Index sets journal_size_limit=64MB on its own connection")
    func searchIndexSetsJournalSizeLimit() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("wal-jsl-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let index = try await Search.Index(dbPath: tempDB)
        let limit = await index.currentJournalSizeLimit()
        await index.disconnect()

        // Cap is 64 MiB so pathological reader-starvation cases can't
        // grow the .db-wal sidecar without bound (the SQLite default
        // is -1 = unlimited).
        #expect(limit == 67108864, "Search.Index should set journal_size_limit=64 MiB (got \(limit ?? -1))")
    }
}
