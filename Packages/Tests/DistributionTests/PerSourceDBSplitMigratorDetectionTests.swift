import Distribution
import Foundation
import SharedConstants
import Testing

// MARK: - PerSourceDBSplitMigrator detection logic tests

//
// Step 6a of `docs/design/per-source-db-split.md`: pure read-only
// detection that decides whether a per-source DB split migration is
// needed for a given base directory. No DB I/O; just filesystem
// checks against the candidate filenames.

@Suite("Distribution.PerSourceDBSplitMigrator.detect (filesystem-only step 6a check)")
struct PerSourceDBSplitMigratorDetectionTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migrator-detect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ url: URL, sizeBytes: Int = 4096) throws {
        let data = Data(count: sizeBytes)
        try data.write(to: url)
    }

    private static let candidateFilenames: [String] = [
        Shared.Constants.FileName.appleDocumentationDatabase,
        Shared.Constants.FileName.higDatabase,
        Shared.Constants.FileName.appleArchiveDatabase,
        Shared.Constants.FileName.swiftEvolutionDatabase,
        Shared.Constants.FileName.swiftDocumentationDatabase,
        Shared.Constants.FileName.appleSampleCodeDatabase,
        Shared.Constants.FileName.swiftPackagesDatabase,
    ]

    @Test("Empty base directory: no legacy DB found")
    func emptyDirReturnsNoLegacyDBFound() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            candidatePerSourceFilenames: Self.candidateFilenames
        )
        #expect(outcome == .noLegacyDBFound)
    }

    @Test("Only legacy search.db, no per-source DBs: migrationNeeded")
    func legacyOnlyReturnsMigrationNeeded() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        try touch(legacy)

        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            candidatePerSourceFilenames: Self.candidateFilenames
        )
        if case let .migrationNeeded(legacyFile) = outcome {
            #expect(legacyFile.lastPathComponent == "search.db")
        } else {
            Issue.record("expected migrationNeeded, got \(outcome)")
        }
    }

    @Test("Legacy search.db plus at least one non-empty per-source DB: alreadyMigrated")
    func legacyPlusPerSourceReturnsAlreadyMigrated() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try touch(dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase))
        try touch(dir.appendingPathComponent(Shared.Constants.FileName.appleDocumentationDatabase))
        try touch(dir.appendingPathComponent(Shared.Constants.FileName.higDatabase))

        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            candidatePerSourceFilenames: Self.candidateFilenames
        )
        if case let .alreadyMigrated(legacyFile, splitFiles) = outcome {
            #expect(legacyFile.lastPathComponent == "search.db")
            #expect(splitFiles.count == 2, "two non-empty per-source DBs present")
        } else {
            Issue.record("expected alreadyMigrated, got \(outcome)")
        }
    }

    @Test("Empty (zero-byte) per-source DB does NOT count as already migrated")
    func zeroBytePerSourceDBIgnoredAsEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try touch(dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase))
        // Create a zero-byte placeholder per-source DB (e.g. crash mid-migration left an empty file).
        try Data().write(to: dir.appendingPathComponent(Shared.Constants.FileName.appleDocumentationDatabase))

        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            candidatePerSourceFilenames: Self.candidateFilenames
        )
        if case .migrationNeeded = outcome {
            // pass
        } else {
            Issue.record("expected migrationNeeded (zero-byte file does not count), got \(outcome)")
        }
    }

    // MARK: - planFromKnownSources stub (step 6a; real query lands in 6b)

    @Test("planFromKnownSources builds a plan with the right rename target + per-source paths")
    func planFromKnownSourcesBuildsExpectedShape() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)

        let plan = Distribution.PerSourceDBSplitMigrator.planFromKnownSources(
            legacyFile: legacy,
            baseDirectory: dir,
            sourceIDsToPlan: [
                (sourceID: "apple-docs", destinationDescriptorID: "apple-documentation", rowCount: 379124),
                (sourceID: "hig", destinationDescriptorID: "hig", rowCount: 247),
                (sourceID: "swift-org", destinationDescriptorID: "swift-documentation", rowCount: 1500),
            ]
        )
        #expect(plan.sourcePlans.count == 3)
        #expect(plan.totalEstimatedRows == 380871)
        #expect(plan.legacyRenameTarget.lastPathComponent == "search.db.legacy-pre-per-source-split")
        let firstPlan = plan.sourcePlans[0]
        #expect(firstPlan.sourceID == "apple-docs")
        #expect(firstPlan.destinationDescriptorID == "apple-documentation")
        #expect(firstPlan.destinationDBPath.lastPathComponent == "apple-documentation.db")
        #expect(firstPlan.estimatedRowCount == 379124)
    }
}
