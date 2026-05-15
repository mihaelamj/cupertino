@testable import Distribution
import DistributionModels
import Foundation
import SharedConstants
import Testing

/// Closure-free no-op observer for `Distribution.SetupService.run` calls
/// in tests that don't care about the events. Replaces the previous
/// trailing-closure `{ _ in }` pattern.
private struct NoopObserver: Distribution.SetupService.EventObserving {
    func observe(event: Distribution.SetupService.Event) {}
}

// MARK: - Backup-existing-DBs (#249)

struct BackupSuffixTests {
    @Test("Includes the installed version + ISO-8601 timestamp")
    func includesVersionAndTimestamp() {
        let date = Date(timeIntervalSince1970: 1777852812) // 2026-05-04T01:00:12Z
        let suffix = Distribution.SetupService.backupSuffix(for: "0.10.0", now: date)
        #expect(suffix.hasPrefix("backup-0.10.0-"))
        #expect(suffix.contains("2026-05-04"))
        // Z-suffix confirms UTC formatting
        #expect(suffix.hasSuffix("Z"))
    }

    @Test("Falls back to 'unknown' when installed version is nil")
    func unknownFallback() {
        let suffix = Distribution.SetupService.backupSuffix(for: nil)
        #expect(suffix.hasPrefix("backup-unknown-"))
    }

    @Test("Two suffixes one second apart are distinct")
    func distinctTimestamps() {
        let earlier = Date(timeIntervalSince1970: 1777852812)
        let later = Date(timeIntervalSince1970: 1777852813)
        let s1 = Distribution.SetupService.backupSuffix(for: "0.10.0", now: earlier)
        let s2 = Distribution.SetupService.backupSuffix(for: "0.10.0", now: later)
        #expect(s1 != s2)
    }
}

struct DBBackupIntegrationTests {
    /// End-to-end against a local file: Run `SetupService.run` with a
    /// pre-existing `search.db` on disk; verify it gets renamed to a
    /// `.backup-*` sibling before the (failed) extract attempt.
    @Test("Pre-existing DBs are renamed to .backup-<version>-<iso8601>")
    func preExistingDBsAreBackedUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dist-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Seed a fake old install with all three DBs (the v0.11+ → v1.0.x
        // upgrade case), plus a version stamp.
        let searchDB = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        let samplesDB = dir.appendingPathComponent(Shared.Constants.FileName.samplesDatabase)
        let packagesDB = dir.appendingPathComponent(Shared.Constants.FileName.packagesIndexDatabase)
        try Data("old-search-db-content".utf8).write(to: searchDB)
        try Data("old-samples-db-content".utf8).write(to: samplesDB)
        try Data("old-packages-db-content".utf8).write(to: packagesDB)
        try Distribution.InstalledVersion.write("0.11.0", in: dir)

        // Run through a localhost release URL that won't actually serve
        // — the run will fail at download, but the backup pass executes
        // first because it's step 0 of the pipeline.
        let request = Distribution.SetupService.Request(
            baseDir: dir,
            currentDocsVersion: "1.0.0", docsReleaseBaseURL: "http://127.0.0.1:1/",
            keepExisting: false
        )

        // We don't care that the run errors at download — only that the
        // backup happened first. Capture the events.
        actor EventCollector {
            var events: [Distribution.SetupService.Event] = []
            func append(_ event: Distribution.SetupService.Event) {
                events.append(event)
            }
        }
        let collector = EventCollector()

        struct CollectingObserver: Distribution.SetupService.EventObserving {
            let collector: EventCollector
            func observe(event: Distribution.SetupService.Event) {
                Task { await collector.append(event) }
            }
        }

        _ = try? await Distribution.SetupService.run(
            request,
            events: CollectingObserver(collector: collector)
        )

        // Give the Task above a moment to flush; cheap polling is fine
        // for a unit test against a localhost-failing URL.
        try await Task.sleep(nanoseconds: 100000000)

        // All three originals should be gone (renamed away).
        #expect(!FileManager.default.fileExists(atPath: searchDB.path))
        #expect(!FileManager.default.fileExists(atPath: samplesDB.path))
        #expect(!FileManager.default.fileExists(atPath: packagesDB.path))

        // Backups should exist with the expected suffix shape for all three.
        let dirContents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let searchBackups = dirContents.filter {
            $0.hasPrefix(Shared.Constants.FileName.searchDatabase + ".backup-0.11.0-")
        }
        let samplesBackups = dirContents.filter {
            $0.hasPrefix(Shared.Constants.FileName.samplesDatabase + ".backup-0.11.0-")
        }
        let packagesBackups = dirContents.filter {
            $0.hasPrefix(Shared.Constants.FileName.packagesIndexDatabase + ".backup-0.11.0-")
        }
        #expect(searchBackups.count == 1, "expected one search.db backup, got \(searchBackups)")
        #expect(samplesBackups.count == 1, "expected one samples.db backup, got \(samplesBackups)")
        #expect(packagesBackups.count == 1, "expected one packages.db backup, got \(packagesBackups)")

        // Backup should still hold the original bytes.
        if let backupName = packagesBackups.first {
            let backupURL = dir.appendingPathComponent(backupName)
            let bytes = try Data(contentsOf: backupURL)
            #expect(String(data: bytes, encoding: .utf8) == "old-packages-db-content")
        }
    }

    /// v0.10.x → v1.0 case: only search.db + samples.db on disk; no
    /// packages.db (didn't exist yet). Backup should skip the missing one.
    @Test("Pre-v0.11 install (no packages.db) backs up only what exists")
    func partialInstallBacksUpOnlyPresent() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dist-backup-partial-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let searchDB = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        let samplesDB = dir.appendingPathComponent(Shared.Constants.FileName.samplesDatabase)
        try Data("old".utf8).write(to: searchDB)
        try Data("old".utf8).write(to: samplesDB)
        try Distribution.InstalledVersion.write("0.10.0", in: dir)

        let request = Distribution.SetupService.Request(
            baseDir: dir,
            currentDocsVersion: "1.0.0", docsReleaseBaseURL: "http://127.0.0.1:1/"
        )
        _ = try? await Distribution.SetupService.run(request, events: NoopObserver())
        try await Task.sleep(nanoseconds: 100000000)

        let dirContents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backups = dirContents.filter { $0.contains(".backup-0.10.0-") }
        // Two backups (search + samples), zero packages.
        #expect(backups.count == 2)
        #expect(backups.contains { $0.hasPrefix(Shared.Constants.FileName.searchDatabase) })
        #expect(backups.contains { $0.hasPrefix(Shared.Constants.FileName.samplesDatabase) })
        #expect(
            !backups.contains { $0.hasPrefix(Shared.Constants.FileName.packagesIndexDatabase) },
            "no packages.db on disk → no packages backup"
        )
    }

    @Test("No-op when DBs don't exist on disk (fresh install)")
    func freshInstallNoOp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dist-backup-fresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // No DBs, no version stamp.
        let request = Distribution.SetupService.Request(
            baseDir: dir,
            currentDocsVersion: "1.0.0", docsReleaseBaseURL: "http://127.0.0.1:1/"
        )

        _ = try? await Distribution.SetupService.run(request, events: NoopObserver())

        // No backup files should appear.
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backups = contents.filter { $0.contains(".backup-") }
        #expect(backups.isEmpty, "fresh install must not create backup files")
    }
}
