@testable import CLI
import Distribution
import Foundation
import LoggingModels
import SampleIndexModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import Testing

// MARK: - cupertino setup post-extract migration hook tests (step 6c-iii)

//
// Verifies CLIImpl.Command.Setup.runPerSourceDBSplitMigrationIfNeeded
// dispatches correctly across the 4 DetectionOutcome cases without
// requiring the full Distribution.SetupService stack.

@Suite("CLIImpl.Command.Setup migration hook: detection + dispatch")
struct SetupMigrationHookTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("setup-migration-hook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeFixtureLegacyDB(
        at path: URL,
        rows: [Distribution.PerSourceDBSplitMigrator.LegacyRow]
    ) async throws {
        let index = try await Search.Index(
            dbPath: path,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        for row in rows {
            try await index.indexDocument(row)
        }
        await index.disconnect()
    }

    @Test("Hook is a no-op when no legacy search.db exists (fresh install / post-v1.3.0 user)")
    func hookNoOpsOnFreshInstall() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // No search.db in the directory; hook should return cleanly.
        try await CLIImpl.Command.Setup.runPerSourceDBSplitMigrationIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )
        // No per-source files should have been created.
        let appleDocPath = dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleDocumentation.filename)
        #expect(!FileManager.default.fileExists(atPath: appleDocPath.path))
    }

    @Test("Hook runs the migration when legacy search.db is detected (end-to-end through Live conformers)")
    func hookRunsMigrationOnLegacyDetected() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyPath = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        try await makeFixtureLegacyDB(at: legacyPath, rows: [
            Distribution.PerSourceDBSplitMigrator.LegacyRow(
                uri: "ad://1",
                source: Shared.Constants.SourcePrefix.appleDocs,
                framework: "F", title: "T", content: "C",
                filePath: "/tmp/f", contentHash: "h", lastCrawled: Date()
            ),
            Distribution.PerSourceDBSplitMigrator.LegacyRow(
                uri: "h://1",
                source: Shared.Constants.SourcePrefix.hig,
                framework: "F", title: "T", content: "C",
                filePath: "/tmp/f", contentHash: "h", lastCrawled: Date()
            ),
        ])

        try await CLIImpl.Command.Setup.runPerSourceDBSplitMigrationIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )

        // Per-source DBs created.
        let appleDocPath = dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleDocumentation.filename)
        let higPath = dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.hig.filename)
        #expect(FileManager.default.fileExists(atPath: appleDocPath.path))
        #expect(FileManager.default.fileExists(atPath: higPath.path))
        // Legacy file renamed to .legacy-pre-per-source-split.
        let renamed = dir.appendingPathComponent("search.db.legacy-pre-per-source-split")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(!FileManager.default.fileExists(atPath: legacyPath.path))
    }

    @Test("Hook is a no-op when alreadyMigrated (legacy + per-source DB both present)")
    func hookNoOpsOnAlreadyMigrated() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Both legacy + at least one per-source file pre-exist; detect()
        // returns .alreadyMigrated; hook logs + returns cleanly.
        try Data("legacy stale".utf8).write(to: dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase))
        try Data("hig stale".utf8).write(to: dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.hig.filename))

        // Capture: just verify the hook returns without throwing + does
        // not touch the legacy file (the alreadyMigrated branch logs +
        // returns without running migrate).
        try await CLIImpl.Command.Setup.runPerSourceDBSplitMigrationIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )
        // Legacy file untouched (not renamed).
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase).path))
        // No `.legacy-pre-per-source-split` rename happened.
        let renamed = dir.appendingPathComponent("search.db.legacy-pre-per-source-split")
        #expect(!FileManager.default.fileExists(atPath: renamed.path))
    }

    // MARK: - #1037 part 4: legacy samples.db filename migration

    @Test("#1037: migrateLegacySamplesDatabaseIfNeeded renames samples.db → apple-sample-code.db when only the legacy file exists")
    func legacySamplesRenamedWhenAloneOnDisk() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyPath = Sample.Index.legacySamplesDatabasePath(baseDirectory: dir)
        let currentPath = Sample.Index.databasePath(baseDirectory: dir)
        // Seed a sentinel byte so the rename is observable end-to-end.
        try Data("legacy-content".utf8).write(to: legacyPath)
        #expect(FileManager.default.fileExists(atPath: legacyPath.path))
        #expect(!FileManager.default.fileExists(atPath: currentPath.path))

        CLIImpl.Command.Setup.migrateLegacySamplesDatabaseIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )

        #expect(!FileManager.default.fileExists(atPath: legacyPath.path), "legacy samples.db should be gone after rename")
        #expect(FileManager.default.fileExists(atPath: currentPath.path), "apple-sample-code.db should now exist")
        // Content survives the rename (it's a file move, not a copy).
        let surviving = try String(contentsOf: currentPath, encoding: .utf8)
        #expect(surviving == "legacy-content")
    }

    @Test("#1037: helper is a no-op when only apple-sample-code.db exists (fresh post-#1037 install)")
    func helperNoOpsOnFreshInstall() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let currentPath = Sample.Index.databasePath(baseDirectory: dir)
        try Data("fresh".utf8).write(to: currentPath)

        CLIImpl.Command.Setup.migrateLegacySamplesDatabaseIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )

        // The new file is untouched.
        #expect(FileManager.default.fileExists(atPath: currentPath.path))
        let surviving = try String(contentsOf: currentPath, encoding: .utf8)
        #expect(surviving == "fresh")
        // No legacy file got conjured.
        let legacyPath = Sample.Index.legacySamplesDatabasePath(baseDirectory: dir)
        #expect(!FileManager.default.fileExists(atPath: legacyPath.path))
    }

    @Test("#1037: helper warns and leaves both files alone when legacy + current both exist")
    func bothFilesExistKeepsBoth() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyPath = Sample.Index.legacySamplesDatabasePath(baseDirectory: dir)
        let currentPath = Sample.Index.databasePath(baseDirectory: dir)
        try Data("legacy".utf8).write(to: legacyPath)
        try Data("current".utf8).write(to: currentPath)

        CLIImpl.Command.Setup.migrateLegacySamplesDatabaseIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )

        // Both files survive; the helper does not destroy data.
        #expect(FileManager.default.fileExists(atPath: legacyPath.path))
        #expect(FileManager.default.fileExists(atPath: currentPath.path))
        // Contents unchanged: helper did not silently overwrite.
        #expect(try String(contentsOf: legacyPath, encoding: .utf8) == "legacy")
        #expect(try String(contentsOf: currentPath, encoding: .utf8) == "current")
    }

    @Test("#1037 round-6 fix: legacy rename also moves -wal and -shm sidecars (data-loss guard)")
    func legacyRenameMovesWALAndSHMSidecars() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyPath = Sample.Index.legacySamplesDatabasePath(baseDirectory: dir)
        let currentPath = Sample.Index.databasePath(baseDirectory: dir)

        // Seed the main file + both SQLite sidecars at the legacy
        // path. A crashed `cupertino save --samples` on pre-#1037 binary
        // would have left this exact shape on disk; the un-checkpointed
        // pages live in samples.db-wal.
        try Data("main".utf8).write(to: legacyPath)
        let legacyWAL = URL(fileURLWithPath: legacyPath.path + "-wal")
        let legacySHM = URL(fileURLWithPath: legacyPath.path + "-shm")
        try Data("wal-content".utf8).write(to: legacyWAL)
        try Data("shm-content".utf8).write(to: legacySHM)

        CLIImpl.Command.Setup.migrateLegacySamplesDatabaseIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )

        // Main file renamed.
        #expect(!FileManager.default.fileExists(atPath: legacyPath.path))
        #expect(FileManager.default.fileExists(atPath: currentPath.path))
        // Sidecars moved with the main file; SQLite WAL recovery on
        // the next open finds apple-sample-code.db-wal and replays
        // the un-checkpointed transactions.
        #expect(!FileManager.default.fileExists(atPath: legacyWAL.path))
        #expect(!FileManager.default.fileExists(atPath: legacySHM.path))
        let currentWAL = URL(fileURLWithPath: currentPath.path + "-wal")
        let currentSHM = URL(fileURLWithPath: currentPath.path + "-shm")
        #expect(FileManager.default.fileExists(atPath: currentWAL.path))
        #expect(FileManager.default.fileExists(atPath: currentSHM.path))
        #expect(try String(contentsOf: currentWAL, encoding: .utf8) == "wal-content")
        #expect(try String(contentsOf: currentSHM, encoding: .utf8) == "shm-content")
    }

    @Test("#1037 round-6 fix: legacy rename tolerates missing sidecars (only main file present)")
    func legacyRenameWithoutSidecars() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyPath = Sample.Index.legacySamplesDatabasePath(baseDirectory: dir)
        let currentPath = Sample.Index.databasePath(baseDirectory: dir)

        // Main file only, no sidecars (a clean save --samples that
        // checkpointed before exiting).
        try Data("main".utf8).write(to: legacyPath)

        CLIImpl.Command.Setup.migrateLegacySamplesDatabaseIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )

        #expect(FileManager.default.fileExists(atPath: currentPath.path))
        let currentWAL = URL(fileURLWithPath: currentPath.path + "-wal")
        let currentSHM = URL(fileURLWithPath: currentPath.path + "-shm")
        #expect(!FileManager.default.fileExists(atPath: currentWAL.path))
        #expect(!FileManager.default.fileExists(atPath: currentSHM.path))
    }

    @Test("#1037: helper is a no-op when neither file exists")
    func helperNoOpsWhenNeitherFileExists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyPath = Sample.Index.legacySamplesDatabasePath(baseDirectory: dir)
        let currentPath = Sample.Index.databasePath(baseDirectory: dir)
        #expect(!FileManager.default.fileExists(atPath: legacyPath.path))
        #expect(!FileManager.default.fileExists(atPath: currentPath.path))

        CLIImpl.Command.Setup.migrateLegacySamplesDatabaseIfNeeded(
            baseDirectory: dir,
            logger: LoggingModels.Logging.NoopRecording()
        )

        // Still none.
        #expect(!FileManager.default.fileExists(atPath: legacyPath.path))
        #expect(!FileManager.default.fileExists(atPath: currentPath.path))
    }
}
