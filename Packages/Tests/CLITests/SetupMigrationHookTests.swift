@testable import CLI
import Distribution
import Foundation
import LoggingModels
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
}
