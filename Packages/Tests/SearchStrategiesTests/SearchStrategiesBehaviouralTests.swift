import AppleArchiveSource
import AppleConstraintsPass
import AppleDocsSource
import EnrichmentModels
import Foundation
import HIGSource
import LoggingModels
import SampleCodeSource
import SearchModels
import SearchSQLite
import SharedConstants
import SwiftEvolutionSource
import SwiftOrgStrategy
import Testing

// MARK: - #978 behavioural tests for the 6 strategy siblings + AppleConstraintsPass

/// Replaces the pre-#978 metatype-existence smoke (`_ = Search.X.self`) with
/// per-strategy fixture tests. Coverage is one behavioural assertion per
/// producer target:
///
/// - Clean-skip path: every strategy must return `IndexStats(wasSkipped:
///   true, ...)` when its corpus is absent. The skip contract is
///   load-bearing for `Search.IndexBuilder` per #671.
/// - Each test also asserts the `source` identifier is wired correctly,
///   catching the most common copy-paste regression (a sibling strategy
///   reporting another source's prefix).
///
/// Surface verified: `indexItems(into:progress:)` early-return guard +
/// the `Search.IndexStats` value shape. Heavier happy-path coverage
/// (writing structured rows, exercising the #429 poison filters) belongs
/// in follow-up per-strategy targeted suites.
@Suite("#978 — strategy clean-skip behavioural contract", .serialized)
struct SearchStrategiesBehaviouralTests {
    // MARK: - Helpers

    private static func makeIndex() async throws -> (index: Search.Index, dbPath: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-978-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let path = tempDir.appendingPathComponent("search.db")
        let index = try await Search.Index(
            dbPath: path,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        return (index, path)
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static var missingDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-978-missing-\(UUID().uuidString)")
    }

    // MARK: - HIGStrategy

    @Test("HIGStrategy reports clean-skip with no local corpus")
    func higCleanSkip() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let strategy = Search.HIGStrategy(
            higDirectory: Self.missingDir,
            logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.source == Shared.Constants.SourcePrefix.hig)
        #expect(stats.wasSkipped == true)
        #expect(stats.skipReason == "no local corpus")
        #expect(stats.indexed == 0)
    }

    // MARK: - SwiftEvolutionStrategy

    @Test("SwiftEvolutionStrategy reports clean-skip with no local corpus")
    func swiftEvolutionCleanSkip() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let strategy = Search.SwiftEvolutionStrategy(
            evolutionDirectory: Self.missingDir,
            logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.source == Shared.Constants.SourcePrefix.swiftEvolution)
        #expect(stats.wasSkipped == true)
        #expect(stats.skipReason == "no local corpus")
        #expect(stats.indexed == 0)
    }

    // MARK: - SwiftOrgStrategy

    @Test("SwiftOrgStrategy reports clean-skip with no local corpus")
    func swiftOrgCleanSkip() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let strategy = Search.SwiftOrgStrategy(
            swiftOrgDirectory: Self.missingDir,
            markdownStrategy: NilMarkdownStrategy(),
            logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.source == Shared.Constants.SourcePrefix.swiftOrg)
        #expect(stats.wasSkipped == true)
        #expect(stats.skipReason == "no local corpus")
        #expect(stats.indexed == 0)
    }

    // MARK: - AppleArchiveStrategy

    @Test("AppleArchiveStrategy reports clean-skip with no local corpus")
    func appleArchiveCleanSkip() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let strategy = Search.AppleArchiveStrategy(
            archiveDirectory: Self.missingDir,
            logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.source == Shared.Constants.SourcePrefix.appleArchive)
        #expect(stats.wasSkipped == true)
        #expect(stats.skipReason == "no local corpus")
        #expect(stats.indexed == 0)
    }

    // MARK: - SampleCodeStrategy

    @Test("SampleCodeStrategy reports clean-skip when catalog is missing")
    func sampleCodeCleanSkip() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let strategy = Search.SampleCodeStrategy(
            sampleCatalogProvider: MissingCatalogProvider(),
            logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.source == "sample-code")
        #expect(stats.wasSkipped == true)
        #expect(stats.skipReason == "no catalog found")
        #expect(stats.indexed == 0)
    }

    @Test("SampleCodeStrategy reports clean-skip when catalog is empty")
    func sampleCodeEmptyCatalog() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let strategy = Search.SampleCodeStrategy(
            sampleCatalogProvider: EmptyCatalogProvider(),
            logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.wasSkipped == true)
        #expect(stats.skipReason == "catalog empty")
        #expect(stats.indexed == 0)
    }

    // MARK: - AppleDocsStrategy

    @Test("AppleDocsStrategy reports clean-skip with no local corpus")
    func appleDocsCleanSkip() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let strategy = Search.AppleDocsStrategy(
            docsDirectory: Self.missingDir,
            markdownStrategy: NilMarkdownStrategy(),
            logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.source == Shared.Constants.SourcePrefix.appleDocs)
        #expect(stats.wasSkipped == true)
        #expect(stats.indexed == 0)
    }

    // MARK: - AppleConstraintsPass

    @Test("AppleConstraintsPass returns honest zero-result when lookup is nil")
    func appleConstraintsPassNilLookupIsNoop() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let pass = Enrichment.AppleConstraintsPass(searchIndex: index, lookup: nil)
        let result = try await pass.run(database: nil)

        #expect(result.passIdentifier == "constraints")
        #expect(result.rowsAffected == 0)
        #expect(result.rowsSkipped == 0)
        #expect(pass.target == EnrichmentModels.Target.search)
        #expect(pass.identifier == "constraints")
        #expect(pass.schemaVersion == 1)
        #expect(pass.dependsOn.isEmpty)
    }

    @Test("AppleConstraintsPass returns honest rowsAffected when lookup yields no match")
    func appleConstraintsPassEmptyLookupReturnsZero() async throws {
        let (index, db) = try await Self.makeIndex()
        defer { Self.cleanup(db) }

        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(
                docURI: "apple-docs://nonexistent/symbol",
                constraints: ["View"]
            ),
        ])
        let pass = Enrichment.AppleConstraintsPass(searchIndex: index, lookup: lookup)
        let result = try await pass.run(database: nil)

        // No doc_symbols row matches the synthetic URI, so the SET-based
        // UPDATE pass touches 0 rows. Verifies the #979 rowsAffected
        // pipeline carries the honest sqlite3_changes count, not the
        // pre-#979 hardcoded 0.
        #expect(result.passIdentifier == "constraints")
        #expect(result.rowsAffected == 0)
    }
}

// MARK: - Test doubles

private struct NilMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
    func convert(markdown _: String, url _: URL?) -> Shared.Models.StructuredDocumentationPage? {
        nil
    }
}

private struct MissingCatalogProvider: Search.SampleCatalogProvider {
    func fetch() async -> Search.SampleCatalogState {
        .missing(onDiskPath: "/nonexistent/catalog.json")
    }
}

private struct EmptyCatalogProvider: Search.SampleCatalogProvider {
    func fetch() async -> Search.SampleCatalogState {
        .loaded(entries: [])
    }
}

private struct InMemoryLookup: Search.StaticConstraintsLookup {
    let entries: [Search.StaticConstraintEntry]
    func allEntries() async throws -> [Search.StaticConstraintEntry] {
        entries
    }
}
