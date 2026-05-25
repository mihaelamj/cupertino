import Distribution
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - PerSourceDBSplitMigrator.migrate() integration tests

//
// Step 6b of `docs/design/per-source-db-split.md`: end-to-end
// coordinator that orchestrates the legacy → per-source DB split via
// two DI seams (LegacyDBReader, PerDBWriter). Step 6c supplies the
// Live conformers backed by SearchSQLite's Search.Index; these tests
// use in-memory fakes to pin the coordinator's semantics.

@Suite("PerSourceDBSplitMigrator.migrate() coordinator (step 6b)")
struct PerSourceDBSplitMigratorMigrateTests {
    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migrator-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touchLegacy(at dir: URL) throws -> URL {
        let legacy = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        try Data("legacy".utf8).write(to: legacy)
        return legacy
    }

    // MARK: - Fake provider + registry

    private struct FakeProvider: Search.SourceProvider {
        let id: String
        let dbDescriptor: Shared.Models.DatabaseDescriptor
        let aliases: Set<String>

        init(id: String, dbDescriptor: Shared.Models.DatabaseDescriptor, aliases: Set<String> = []) {
            self.id = id
            self.dbDescriptor = dbDescriptor
            self.aliases = aliases
        }

        var legacySourceIDAliases: Set<String> {
            aliases
        }

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

    // MARK: - Fake reader + writer

    private final class FakeLegacyReader: Distribution.PerSourceDBSplitMigrator.LegacyDBReader, @unchecked Sendable {
        private let rowsBySource: [String: [Distribution.PerSourceDBSplitMigrator.LegacyRow]]

        init(rowsBySource: [String: [Distribution.PerSourceDBSplitMigrator.LegacyRow]]) {
            self.rowsBySource = rowsBySource
        }

        func sourceIDCounts() async throws -> [String: Int] {
            rowsBySource.mapValues(\.count)
        }

        func rows(forSourceID sourceID: String) -> AsyncThrowingStream<Distribution.PerSourceDBSplitMigrator.LegacyRow, Error> {
            let rows = rowsBySource[sourceID] ?? []
            return AsyncThrowingStream { continuation in
                for row in rows {
                    continuation.yield(row)
                }
                continuation.finish()
            }
        }
    }

    private final class FakePerDBWriter: Distribution.PerSourceDBSplitMigrator.PerDBWriter, @unchecked Sendable {
        let destination: Shared.Models.DatabaseDescriptor
        let destinationPath: URL
        var written: [Distribution.PerSourceDBSplitMigrator.LegacyRow] = []
        var disconnectCalled = false

        init(destination: Shared.Models.DatabaseDescriptor, destinationPath: URL) {
            self.destination = destination
            self.destinationPath = destinationPath
        }

        func write(_ row: Distribution.PerSourceDBSplitMigrator.LegacyRow) async throws {
            written.append(row)
            // Touch the destination file so fileManager.attributesOfItem returns a non-zero size.
            if !FileManager.default.fileExists(atPath: destinationPath.path) {
                try Data("destination".utf8).write(to: destinationPath)
            }
        }

        func rowCount() async throws -> Int {
            written.count
        }

        func disconnect() async {
            disconnectCalled = true
        }
    }

    private static func makeRow(uri: String, source: String) -> Distribution.PerSourceDBSplitMigrator.LegacyRow {
        // LegacyRow = Search.IndexDocumentParams (full-fidelity typealias)
        Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: uri,
            source: source,
            framework: "FixtureFramework",
            title: "Fixture \(uri)",
            content: "Content for \(uri)",
            filePath: "/tmp/\(uri)",
            contentHash: "hash-\(uri)",
            lastCrawled: Date()
        )
    }

    // MARK: - Tests

    @Test("Happy path: 2 known sources, rows copy correctly + counts verify + legacy renamed")
    func happyPathTwoKnownSources() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try touchLegacy(at: dir)

        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "fake-apple-docs", dbDescriptor: .appleDocumentation))
        registry.register(FakeProvider(id: "fake-hig", dbDescriptor: .hig))

        let reader = FakeLegacyReader(rowsBySource: [
            "fake-apple-docs": [
                Self.makeRow(uri: "ad://1", source: "fake-apple-docs"),
                Self.makeRow(uri: "ad://2", source: "fake-apple-docs"),
            ],
            "fake-hig": [
                Self.makeRow(uri: "hig://1", source: "fake-hig"),
            ],
        ])

        let outcome = try await Distribution.PerSourceDBSplitMigrator.migrate(
            legacyFile: legacy,
            baseDirectory: dir,
            registry: registry,
            reader: reader,
            writerFactory: { destination, path in
                FakePerDBWriter(destination: destination, destinationPath: path)
            }
        )

        #expect(outcome.results.count == 2)
        #expect(outcome.totalRowsWritten == 3)
        #expect(outcome.legacyFileRenamed == true)
        #expect(outcome.actualLegacyRenameTarget?.lastPathComponent == "search.db.legacy-pre-per-source-split")

        // Legacy file should no longer exist at the original path.
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        // Renamed file IS on disk.
        let renamed = dir.appendingPathComponent("search.db.legacy-pre-per-source-split")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    @Test("View-source pattern: two source-ids sharing one destinationDB get ONE writer call, both sources' rows preserved")
    func viewSourceTwoSourceIDsShareOneWriter() async throws {
        // Load-bearing test for step-6c-ii critic-fix round-1 finding #1.
        // Pre-fix, migrate() called writerFactory twice for the same
        // destinationPath (once per source-id); a factory implementation
        // that cleared the destination file on each call would silently
        // drop the first source's rows. Post-fix, migrate() groups
        // source-plans by destinationPath and calls the factory ONCE
        // per group; multiple sources stream through the same writer.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try touchLegacy(at: dir)

        var registry = Search.SourceRegistry()
        // Two FakeProviders sharing the same destinationDB (mirrors
        // the production swift-org + swift-book → .swiftDocumentation
        // view-source pattern).
        registry.register(FakeProvider(id: "fake-swift-org", dbDescriptor: .swiftDocumentation))
        registry.register(FakeProvider(id: "fake-swift-book", dbDescriptor: .swiftDocumentation))

        let reader = FakeLegacyReader(rowsBySource: [
            "fake-swift-org": [
                Self.makeRow(uri: "so://1", source: "fake-swift-org"),
                Self.makeRow(uri: "so://2", source: "fake-swift-org"),
            ],
            "fake-swift-book": [
                Self.makeRow(uri: "sb://1", source: "fake-swift-book"),
            ],
        ])

        // Track factory invocations to verify the grouping.
        final class FactoryCallCounter: @unchecked Sendable {
            var invocationsByPath: [URL: Int] = [:]
        }
        let counter = FactoryCallCounter()

        let outcome = try await Distribution.PerSourceDBSplitMigrator.migrate(
            legacyFile: legacy,
            baseDirectory: dir,
            registry: registry,
            reader: reader,
            writerFactory: { destination, path in
                counter.invocationsByPath[path, default: 0] += 1
                return FakePerDBWriter(destination: destination, destinationPath: path)
            }
        )

        // EXACTLY ONE factory call per destinationPath, regardless of
        // how many source-ids share it.
        #expect(counter.invocationsByPath.count == 1, "all sources share one destination → one factory invocation")
        #expect(counter.invocationsByPath.values.first == 1, "factory called exactly once for the shared destination")

        // Outcome has one SourceResult per source-plan; total rows = 3.
        #expect(outcome.results.count == 2)
        #expect(outcome.totalRowsWritten == 3, "both sources' rows preserved (swift-org=2 + swift-book=1)")
        #expect(outcome.legacyFileRenamed == true)
    }

    @Test("Unknown source-id (not in registry) throws MigrationError.unknownSourceIDs by default")
    func unknownSourceIDThrowsByDefault() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try touchLegacy(at: dir)

        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "fake-known", dbDescriptor: .hig))

        let reader = FakeLegacyReader(rowsBySource: [
            "fake-known": [Self.makeRow(uri: "k://1", source: "fake-known")],
            "fake-unknown": [Self.makeRow(uri: "u://1", source: "fake-unknown")],
        ])

        await #expect(throws: Distribution.PerSourceDBSplitMigrator.MigrationError.self) {
            _ = try await Distribution.PerSourceDBSplitMigrator.migrate(
                legacyFile: legacy,
                baseDirectory: dir,
                registry: registry,
                reader: reader,
                writerFactory: { destination, path in
                    FakePerDBWriter(destination: destination, destinationPath: path)
                }
            )
        }

        // Legacy file MUST remain in place (no partial migration).
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("tolerateUnknownSourceIDs: true skips unknowns and completes for known sources")
    func tolerateUnknownsCompletesForKnown() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try touchLegacy(at: dir)

        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "fake-known", dbDescriptor: .hig))

        let reader = FakeLegacyReader(rowsBySource: [
            "fake-known": [Self.makeRow(uri: "k://1", source: "fake-known")],
            "fake-unknown": [Self.makeRow(uri: "u://1", source: "fake-unknown")],
        ])

        let outcome = try await Distribution.PerSourceDBSplitMigrator.migrate(
            legacyFile: legacy,
            baseDirectory: dir,
            registry: registry,
            reader: reader,
            writerFactory: { destination, path in
                FakePerDBWriter(destination: destination, destinationPath: path)
            },
            tolerateUnknownSourceIDs: true
        )

        #expect(outcome.results.count == 1, "only fake-known should have been processed")
        #expect(outcome.totalRowsWritten == 1)
        #expect(outcome.legacyFileRenamed == true)
    }

    @Test("Row-count mismatch aborts BEFORE legacy rename; legacy file stays in place")
    func rowCountMismatchAbortsBeforeRename() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try touchLegacy(at: dir)

        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "fake-src", dbDescriptor: .hig))

        // Reader reports 5 rows in sourceIDCounts but yields only 3 from rows(forSourceID:).
        // This synthesizes a count-mismatch: estimated 5, actual 3.
        final class MismatchingReader: Distribution.PerSourceDBSplitMigrator.LegacyDBReader, @unchecked Sendable {
            func sourceIDCounts() async throws -> [String: Int] {
                ["fake-src": 5]
            }

            func rows(forSourceID _: String) -> AsyncThrowingStream<Distribution.PerSourceDBSplitMigrator.LegacyRow, Error> {
                AsyncThrowingStream { continuation in
                    for index in 0..<3 {
                        continuation.yield(Distribution.PerSourceDBSplitMigrator.LegacyRow(
                            uri: "x://\(index)",
                            source: "fake-src",
                            framework: "f", title: "t", content: "c",
                            filePath: "/", contentHash: "h", lastCrawled: Date()
                        ))
                    }
                    continuation.finish()
                }
            }
        }

        await #expect(throws: Distribution.PerSourceDBSplitMigrator.MigrationError.self) {
            _ = try await Distribution.PerSourceDBSplitMigrator.migrate(
                legacyFile: legacy,
                baseDirectory: dir,
                registry: registry,
                reader: MismatchingReader(),
                writerFactory: { destination, path in
                    FakePerDBWriter(destination: destination, destinationPath: path)
                }
            )
        }

        // Legacy file MUST remain (no partial-rename).
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("legacySourceIDAliases: legacy literal tags route to alias-claiming provider's destinationDB")
    func legacyAliasRoutesToProviderDestination() async throws {
        // Load-bearing test for step-6c-ii critic-fix round-2 finding #1.
        // Mirrors the production failure mode: SampleCodeStrategy emits
        // rows tagged `source = "sample-code"` while
        // SampleCodeSource.definition.id = "samples". Without the
        // legacySourceIDAliases registry-driven lookup, those rows
        // would surface as unknownSourceIDs and the migration would
        // abort.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try touchLegacy(at: dir)

        var registry = Search.SourceRegistry()
        // Provider's definition.id is "fake-samples" but its strategy
        // historically tagged rows "fake-sample-code". The alias claim
        // makes those rows route correctly.
        registry.register(FakeProvider(
            id: "fake-samples",
            dbDescriptor: .appleSampleCodeSearch,
            aliases: ["fake-sample-code"]
        ))

        let reader = FakeLegacyReader(rowsBySource: [
            // Both the canonical id AND the legacy alias appear in
            // counts; both should route to the same provider's destination.
            "fake-samples": [
                Self.makeRow(uri: "s://canonical/1", source: "fake-samples"),
            ],
            "fake-sample-code": [
                Self.makeRow(uri: "s://alias/1", source: "fake-sample-code"),
                Self.makeRow(uri: "s://alias/2", source: "fake-sample-code"),
            ],
        ])

        // Track factory invocations to verify the alias is collapsed
        // into one writer per destination (the canonical + alias rows
        // share one destinationDB).
        final class FactoryCallCounter: @unchecked Sendable {
            var invocationsByPath: [URL: Int] = [:]
        }
        let counter = FactoryCallCounter()

        let outcome = try await Distribution.PerSourceDBSplitMigrator.migrate(
            legacyFile: legacy,
            baseDirectory: dir,
            registry: registry,
            reader: reader,
            writerFactory: { destination, path in
                counter.invocationsByPath[path, default: 0] += 1
                return FakePerDBWriter(destination: destination, destinationPath: path)
            }
        )

        // ONE factory call (canonical + alias collapse to one provider
        // → one destination).
        #expect(counter.invocationsByPath.count == 1)
        #expect(counter.invocationsByPath.values.first == 1)

        // ONE result row (the alias collapses into the canonical
        // provider's SourcePlan), total 3 rows written (1 canonical + 2
        // alias).
        #expect(outcome.results.count == 1)
        #expect(outcome.totalRowsWritten == 3, "1 canonical row + 2 alias rows all routed correctly")
        // The canonical sourceID, NOT the alias literal, is what the
        // SourceResult is keyed under.
        #expect(outcome.results.first?.sourceID == "fake-samples")
        #expect(outcome.legacyFileRenamed == true)
    }

    @Test("legacySourceIDAliases: alias-only rows (no canonical-id rows) still route correctly")
    func legacyAliasOnlyRowsRoute() async throws {
        // Reflects the realistic shape of legacy search.db today:
        // SampleCodeStrategy ALWAYS tags rows "sample-code"; the
        // canonical id "samples" never appears in
        // legacy docs_metadata.source. The migrator must still resolve.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try touchLegacy(at: dir)

        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(
            id: "fake-samples",
            dbDescriptor: .appleSampleCodeSearch,
            aliases: ["fake-sample-code"]
        ))

        let reader = FakeLegacyReader(rowsBySource: [
            "fake-sample-code": [
                Self.makeRow(uri: "s://alias/1", source: "fake-sample-code"),
                Self.makeRow(uri: "s://alias/2", source: "fake-sample-code"),
            ],
        ])

        let outcome = try await Distribution.PerSourceDBSplitMigrator.migrate(
            legacyFile: legacy,
            baseDirectory: dir,
            registry: registry,
            reader: reader,
            writerFactory: { destination, path in
                FakePerDBWriter(destination: destination, destinationPath: path)
            }
        )

        #expect(outcome.results.count == 1, "alias-only rows still produce a result keyed under the canonical id")
        #expect(outcome.results.first?.sourceID == "fake-samples")
        #expect(outcome.totalRowsWritten == 2)
        #expect(outcome.legacyFileRenamed == true)
    }

    @Test("Empty legacy DB: outcome has zero results, legacy still renamed")
    func emptyLegacyDBRenamesWithNoResults() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try touchLegacy(at: dir)

        let registry = Search.SourceRegistry()
        let reader = FakeLegacyReader(rowsBySource: [:])

        let outcome = try await Distribution.PerSourceDBSplitMigrator.migrate(
            legacyFile: legacy,
            baseDirectory: dir,
            registry: registry,
            reader: reader,
            writerFactory: { destination, path in
                FakePerDBWriter(destination: destination, destinationPath: path)
            }
        )

        #expect(outcome.results.isEmpty)
        #expect(outcome.totalRowsWritten == 0)
        #expect(outcome.legacyFileRenamed == true, "empty legacy still gets renamed; future runs see noLegacyDBFound")
    }
}
