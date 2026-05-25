@testable import CLI
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import Testing

// MARK: - #1033 every-source-finds-itself roundtrip pin

/// Post-#1007 source-unification critic gap (raised by the user after
/// the epic closed): the per-source target shape pins
/// (Issue1008-Issue1023) and the registry-derivation pins
/// (Issue1025-Issue1029) cover *structure*, but no test exercised
/// the load-bearing *behavioural* invariant: every source registered
/// in the production registry can find itself in search.db via the
/// canonical write -> query -> assert flow, with the `source` column
/// roundtripping unaliased.
///
/// This suite closes that gap with 4 pins:
///   1. Per-source write-read roundtrip (the registry-iterated sweep).
///   2. Cross-source query covers all search.db-destined sources.
///   3. Per-source `--source X` filter is exact (no leakage).
///   4. PackagesSource is correctly excluded from the search.db indexer
///      dict by the `destinationDB == .search` gate.
///
/// **Out of scope intentionally**: cross-source ranking behavior (the
/// `SourceProperties` 8-axis weights + `intentPriority` map at query
/// time). That's a separate search-quality concern; a regression there
/// would surface in the live MCP / CLI ranking output and belongs in
/// a search-quality test suite, not a source-unification suite.
@Suite("#1033: every source can find itself in search.db (roundtrip)")
struct Issue1033AllSourcesRoundtripTests {
    // MARK: - Helpers

    /// Open a fresh temp search.db with the production indexer dict
    /// + sourceLookup derived from the registry (post-#1027 / #1025).
    private func makeFreshIndex() async throws -> (Search.Index, URL) {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue1033-\(UUID().uuidString).db")
        let registry = CLIImpl.makeProductionSourceRegistry()
        let indexers: [String: any Search.SourceIndexer] = registry.allEnabled
            .filter { $0.destinationDB == .search }
            .reduce(into: [:]) { dict, provider in
                dict[provider.definition.id] = provider.makeIndexer()
            }
        let lookup = Search.SourceLookup(definitions: registry.allEnabled.map(\.definition))
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: indexers,
            sourceLookup: lookup
        )
        return (index, dbPath)
    }

    /// Source-ids the test sweep iterates: every provider in the
    /// production registry whose `destinationDB == .search`. Derived,
    /// not hardcoded: adding a new search-bound source automatically
    /// joins the sweep via this filter.
    private var searchDBSourceIDs: [String] {
        CLIImpl.makeProductionSourceRegistry().allEnabled
            .filter { $0.destinationDB == .search }
            .map(\.definition.id)
    }

    // MARK: - Pin 1: per-source write-read roundtrip

    @Test("Each registered search.db source roundtrips: write tagged row, query, source-id unchanged")
    func eachSourceRoundtripsItsSourceTag() async throws {
        for sourceID in searchDBSourceIDs {
            let (index, dbPath) = try await makeFreshIndex()
            defer { try? FileManager.default.removeItem(at: dbPath) }

            let uniqueTitle = "Issue1033FixtureFor_\(sourceID.replacingOccurrences(of: "-", with: "_"))"
            try await index.indexDocument(Search.IndexDocumentParams(
                uri: "\(sourceID)://issue-1033/fixture",
                source: sourceID,
                framework: "FixtureFramework",
                title: uniqueTitle,
                content: "Fixture content for \(sourceID). The roundtrip pin asserts the source column is intact.",
                filePath: "/tmp/issue-1033-\(sourceID)",
                contentHash: "issue-1033-\(sourceID)",
                lastCrawled: Date()
            ))
            await index.disconnect()

            let reopenIndex = try await Search.Index(
                dbPath: dbPath,
                logger: LoggingModels.Logging.NoopRecording(),
                indexers: [:],
                sourceLookup: .empty
            )
            // includeArchive: true so apple-archive's row isn't silently
            // dropped by the default-false filter (Search.Index.search
            // line 35).
            let results = try await reopenIndex.search(query: uniqueTitle, includeArchive: true)
            await reopenIndex.disconnect()

            #expect(results.count >= 1, "source '\(sourceID)' must find its own fixture row")
            let hit = results.first { $0.source == sourceID }
            #expect(hit != nil, "source '\(sourceID)' must roundtrip its source-id tag (no aliasing); got sources \(results.map(\.source))")
        }
    }

    // MARK: - Pin 2: cross-source query covers all search.db sources

    @Test("Cross-source query (no --source filter) returns rows from every search.db-destined source")
    func crossSourceQueryReturnsAllSources() async throws {
        let (index, dbPath) = try await makeFreshIndex()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        // Write one fixture row per search.db source with a SHARED title term so
        // a single query returns all of them.
        let sharedTerm = "Issue1033SharedFixtureTerm"
        for sourceID in searchDBSourceIDs {
            try await index.indexDocument(Search.IndexDocumentParams(
                uri: "\(sourceID)://issue-1033/shared",
                source: sourceID,
                framework: "Shared",
                title: "\(sharedTerm) for \(sourceID)",
                content: "Cross-source roundtrip body for \(sourceID).",
                filePath: "/tmp/issue-1033-shared-\(sourceID)",
                contentHash: "issue-1033-shared-\(sourceID)",
                lastCrawled: Date()
            ))
        }
        await index.disconnect()

        let reopenIndex = try await Search.Index(
            dbPath: dbPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        // includeArchive: true so apple-archive isn't dropped by the
        // default-false filter on Search.Index.search.
        let results = try await reopenIndex.search(query: sharedTerm, includeArchive: true)
        await reopenIndex.disconnect()

        let returnedSources = Set(results.map(\.source))
        let expectedSources = Set(searchDBSourceIDs)
        #expect(returnedSources == expectedSources, "Cross-source query must return every search.db source's row; expected \(expectedSources), got \(returnedSources)")
    }

    // MARK: - Pin 3: per-source filter is exact (no leakage)

    @Test("Per-source --source filter returns ONLY the requested source (no cross-source leakage)")
    func perSourceFilterIsExact() async throws {
        let (index, dbPath) = try await makeFreshIndex()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let sharedTerm = "Issue1033FilterFixtureTerm"
        for sourceID in searchDBSourceIDs {
            try await index.indexDocument(Search.IndexDocumentParams(
                uri: "\(sourceID)://issue-1033/filter",
                source: sourceID,
                framework: "FilterFixture",
                title: "\(sharedTerm) for \(sourceID)",
                content: "Per-source filter body for \(sourceID).",
                filePath: "/tmp/issue-1033-filter-\(sourceID)",
                contentHash: "issue-1033-filter-\(sourceID)",
                lastCrawled: Date()
            ))
        }
        await index.disconnect()

        let reopenIndex = try await Search.Index(
            dbPath: dbPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )

        for sourceID in searchDBSourceIDs {
            // includeArchive: true so apple-archive's own --source filter works.
            let results = try await reopenIndex.search(query: sharedTerm, source: sourceID, includeArchive: true)
            #expect(results.count >= 1, "Filter '--source \(sourceID)' must return at least 1 row")
            #expect(results.allSatisfy { $0.source == sourceID }, "Filter '--source \(sourceID)' must return ONLY rows from that source; got \(results.map(\.source))")
        }

        await reopenIndex.disconnect()
    }

    // MARK: - Pin 4: PackagesSource excluded from search.db indexer dict

    @Test("PackagesSource is NOT in the search.db indexer dict (destinationDB == .packages excludes it)")
    func packagesSourceExcludedFromSearchDBIndexerDict() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let dict: [String: any Search.SourceIndexer] = registry.allEnabled
            .filter { $0.destinationDB == .search }
            .reduce(into: [:]) { partial, provider in
                partial[provider.definition.id] = provider.makeIndexer()
            }
        #expect(
            !dict.keys.contains(Shared.Constants.SourcePrefix.packages),
            "PackagesSource's source-id 'packages' must NOT appear in the search.db indexer dict; PackagesSource declares destinationDB = .packages"
        )
        // Defence-in-depth: PackagesSource IS in the registry, just not in the search-filtered dict.
        let packagesProvider = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.packages }
        #expect(packagesProvider?.destinationDB == .packages, "PackagesSource must still be registered with destinationDB == .packages")
    }
}
