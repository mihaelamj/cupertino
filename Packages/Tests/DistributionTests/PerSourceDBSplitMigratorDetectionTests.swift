import Distribution
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - PerSourceDBSplitMigrator detection logic tests

//
// Step 6a of `docs/design/per-source-db-split.md`: pure read-only
// detection that decides whether a per-source DB split migration is
// needed for a given base directory. No DB I/O; the migrator derives
// the split-destination filename list from the supplied
// Search.SourceRegistry (registry is the single source of truth).
//
// Test fixture: a fake registry holding a single FakeProvider that
// declares destinationDB = .appleDocumentation (a non-search,
// non-packages descriptor). That's enough to exercise the detection
// rule; production registries with all 8 sources work the same way.

@Suite("Distribution.PerSourceDBSplitMigrator.detect (registry-derived; filesystem-only step 6a check)")
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

    // MARK: - Test-local fake providers

    ///
    /// The migrator only inspects `destinationDB` on each provider, so
    /// the fake just needs to declare a destinationDB. All other
    /// protocol requirements get sentinel values; the migrator never
    /// exercises them.
    private struct FakeProvider: Search.SourceProvider {
        let id: String
        let dbDescriptor: Shared.Models.DatabaseDescriptor

        var definition: Search.SourceDefinition {
            Search.SourceDefinition(
                id: id,
                displayName: id,
                emoji: "🔧",
                properties: Search.SourceProperties(
                    authority: 0.5, freshness: 0.5, comprehensiveness: 0.5,
                    codeExamples: 0.0, hasAvailability: 0.0,
                    designFocus: 0.0, languageFocus: 0.0, searchQuality: 0.5
                ),
                intents: [.apiReference]
            )
        }

        var fetchInfo: Search.FetchInfo? {
            nil
        }

        var destinationDB: Shared.Models.DatabaseDescriptor {
            dbDescriptor
        }

        var capabilities: Search.Capabilities {
            .empty
        }

        func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
            FakeStrategy(source: id)
        }

        func makeIndexer() -> any Search.SourceIndexer {
            FakeIndexer(sourceID: id)
        }
    }

    private struct FakeStrategy: Search.SourceIndexingStrategy {
        let source: String
        func indexItems(
            into _: any Search.Database & Search.IndexWriter,
            progress _: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats {
            Search.IndexStats(source: source, indexed: 0, skipped: 0, wasSkipped: true, skipReason: "fake")
        }
    }

    private struct FakeIndexer: Search.SourceIndexer {
        let sourceID: String
        var displayName: String {
            sourceID
        }

        func extractCode(
            documentID _: Int,
            content _: String,
            uri _: String,
            defaultFramework _: String?
        ) -> Search.ExtractedContent? {
            nil
        }
    }

    /// Registry holding ONE fake provider pointed at `.appleDocumentation`.
    /// Sufficient for the detection tests: the migrator only needs to
    /// know one valid split destination to verify the `alreadyMigrated`
    /// vs `migrationNeeded` branch.
    private func makeFixtureRegistry() -> Search.SourceRegistry {
        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "fake-apple-docs", dbDescriptor: .appleDocumentation))
        return registry
    }

    @Test("Empty base directory: no legacy DB found")
    func emptyDirReturnsNoLegacyDBFound() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            registry: makeFixtureRegistry()
        )
        #expect(outcome == .noLegacyDBFound)
    }

    @Test("Only legacy search.db, no per-source DBs: migrationNeeded")
    func legacyOnlyReturnsMigrationNeeded() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try touch(dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase))
        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            registry: makeFixtureRegistry()
        )
        if case let .migrationNeeded(legacyFile) = outcome {
            #expect(legacyFile.lastPathComponent == "search.db")
        } else {
            Issue.record("expected migrationNeeded, got \(outcome)")
        }
    }

    @Test("Legacy search.db plus at least one non-empty per-source DB: alreadyMigrated (registry-derived list)")
    func legacyPlusPerSourceReturnsAlreadyMigrated() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try touch(dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase))
        // The fake registry declares .appleDocumentation as a split destination;
        // touch its file to trigger the alreadyMigrated branch.
        try touch(dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleDocumentation.filename))
        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            registry: makeFixtureRegistry()
        )
        if case let .alreadyMigrated(legacyFile, splitFiles) = outcome {
            #expect(legacyFile.lastPathComponent == "search.db")
            #expect(splitFiles.count == 1)
            #expect(splitFiles[0].lastPathComponent == "apple-documentation.db")
        } else {
            Issue.record("expected alreadyMigrated, got \(outcome)")
        }
    }

    @Test("Empty (zero-byte) per-source DB does NOT count as already migrated")
    func zeroBytePerSourceDBIgnoredAsEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try touch(dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase))
        try Data().write(to: dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleDocumentation.filename))
        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            registry: makeFixtureRegistry()
        )
        if case .migrationNeeded = outcome {
            // pass
        } else {
            Issue.record("expected migrationNeeded (zero-byte file does not count), got \(outcome)")
        }
    }

    @Test("Registry-derived split destinations EXCLUDE .packages and .search")
    func registryDerivedExcludesPackagesAndSearch() throws {
        // A registry with a provider pointing at .packages and another at .search
        // must NOT cause those filenames to count as split destinations.
        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "fake-packages", dbDescriptor: .packages))
        registry.register(FakeProvider(id: "fake-samples", dbDescriptor: .search))
        registry.register(FakeProvider(id: "fake-real-split", dbDescriptor: .hig))

        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try touch(dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase))
        // Touching packages.db / samples.db (the legacy-source-equivalent at .search)
        // must NOT trigger alreadyMigrated. Only touching hig.db (a real split dest)
        // would. We touch neither: should be migrationNeeded.
        try touch(dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.packages.filename))
        try touch(dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.samples.filename))

        let outcome = Distribution.PerSourceDBSplitMigrator.detect(
            inBaseDirectory: dir,
            registry: registry
        )
        if case .migrationNeeded = outcome {
            // pass: presence of packages.db / samples.db is irrelevant; .hig is
            // the only real split destination from this registry, and it's absent.
        } else {
            Issue.record("expected migrationNeeded (packages.db + samples.db must not count as split destinations), got \(outcome)")
        }
    }

    // MARK: - planFromLegacySourceIDCounts (registry-derived)

    @Test("planFromLegacySourceIDCounts resolves source-ids to destinations via the registry")
    func planFromLegacyCountsResolvesViaRegistry() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)

        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "fake-apple-docs", dbDescriptor: .appleDocumentation))
        registry.register(FakeProvider(id: "fake-hig", dbDescriptor: .hig))

        let plan = Distribution.PerSourceDBSplitMigrator.planFromLegacySourceIDCounts(
            legacyFile: legacy,
            baseDirectory: dir,
            registry: registry,
            legacySourceIDRowCounts: [
                "fake-apple-docs": 379124,
                "fake-hig": 247,
            ]
        )
        #expect(plan.sourcePlans.count == 2)
        #expect(plan.totalEstimatedRows == 379371)
        #expect(plan.legacyRenameTarget.lastPathComponent == "search.db.legacy-pre-per-source-split")
        // The migrator derived destination filenames from the registry's
        // descriptor.filename, NOT from a "<id>.db" template.
        let docsPlan = try #require(plan.sourcePlans.first { $0.sourceID == "fake-apple-docs" })
        #expect(docsPlan.destinationDescriptorID == "apple-documentation")
        #expect(docsPlan.destinationDBPath.lastPathComponent == "apple-documentation.db")
        #expect(docsPlan.estimatedRowCount == 379124)
    }

    @Test("planFromLegacySourceIDCounts drops source-ids the registry does not recognise")
    func planDropsUnknownSourceIDs() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)

        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "fake-known", dbDescriptor: .hig))

        let plan = Distribution.PerSourceDBSplitMigrator.planFromLegacySourceIDCounts(
            legacyFile: legacy,
            baseDirectory: dir,
            registry: registry,
            legacySourceIDRowCounts: [
                "fake-known": 100,
                "fake-unknown": 50,
            ]
        )
        #expect(plan.sourcePlans.count == 1, "unknown source-id must be excluded from the plan; callers surface unknowns via MigrationError.unknownSourceIDs")
        #expect(plan.sourcePlans[0].sourceID == "fake-known")
        #expect(plan.totalEstimatedRows == 100)
    }
}
