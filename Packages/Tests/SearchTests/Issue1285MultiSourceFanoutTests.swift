import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SharedConstants
import SQLite3
import Testing

// MARK: - #1285 — hermetic production multi-source fan-out + merge

///
/// Rank fusion (RRF) math is well covered with MOCK fetchers, but the only test
/// that wired REAL multi-source DBs through the production composition was the
/// snapshot-gated CLI `Enrichment21RankFusionTests` (skips in CI, asserts loose
/// properties). This builds small REAL per-source search DBs in a temp dir,
/// indexes them through the production write path (`Search.Index.indexDocument`),
/// opens them read-only, wires the production fetcher (`Search.DocsSourceCandidateFetcher`)
/// and the production fan-out engine (`Search.SmartQuery`), and asserts the
/// query fans out across all wired sources and merges into one ranked list, with
/// a stable (deterministic) order. Runs on every PR; no snapshot gate.
@Suite("#1285 — production multi-source fan-out merges real per-source DBs")
struct Issue1285MultiSourceFanoutTests {
    /// One real per-source search DB: indexed through the production write path
    /// so it carries a genuine `docs_metadata` + `docs_fts` row matching
    /// `query`, then reopened read-only (the production read shape).
    private func makeIndexedSourceDB(source: String, uriHost: String, query: String) async throws -> Search.Index {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("fanout-1285-\(source)-\(UUID().uuidString).db")
        let writer = try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await writer.indexDocument(Search.IndexDocumentParams(
            uri: "\(uriHost)://\(source)-doc",
            source: source,
            framework: "testkit",
            title: "\(query.capitalized) in \(source)",
            content: "A document about \(query) provided by the \(source) source.",
            filePath: "/tmp/\(source)",
            contentHash: "hash-\(source)",
            lastCrawled: Date(timeIntervalSince1970: 1700000000)
        ))
        await writer.disconnect()

        // Reopen read-only: the production read/serve shape (#1194).
        return try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty,
            readOnly: true
        )
    }

    @Test("a bare query fans out across all wired sources and merges into one ranked list")
    func fanoutMergesRealPerSourceDBs() async throws {
        let query = "observable"
        // Three real per-source DBs, the production per-source-DB shape (#1036).
        let wired: [(source: String, host: String)] = [
            ("apple-docs", "apple-docs"),
            ("hig", "hig"),
            ("swift-evolution", "swift-evolution"),
        ]
        var indexes: [Search.Index] = []
        defer { for index in indexes {
            Task { await index.disconnect() }
        } }

        var fetchers: [any Search.CandidateFetcher] = []
        for entry in wired {
            let index = try await makeIndexedSourceDB(source: entry.source, uriHost: entry.host, query: query)
            indexes.append(index)
            fetchers.append(Search.DocsSourceCandidateFetcher(searchIndex: index, source: entry.source))
        }

        // The production fan-out engine.
        let smartQuery = Search.SmartQuery(fetchers: fetchers)
        let result = await smartQuery.answer(question: query, limit: 20, perFetcherLimit: 10)

        // Fan-out: every wired source contributed.
        let contributing = Set(result.contributingSources)
        for entry in wired {
            #expect(contributing.contains(entry.source), "source \(entry.source) did not contribute to the fan-out")
        }

        // Merge: the single fused list draws from more than one source.
        let candidateSources = Set(result.candidates.map(\.candidate.source))
        #expect(candidateSources.count == wired.count, "fused list did not span all sources: \(candidateSources)")
        #expect(result.candidates.count >= wired.count, "fewer fused candidates than wired sources")

        // Deterministic order: the same inputs fuse to the same ranked order
        // (no random tie-breaking), the "ideally a stable order" property.
        let secondRun = await smartQuery.answer(question: query, limit: 20, perFetcherLimit: 10)
        #expect(
            result.candidates.map(\.candidate.identifier) == secondRun.candidates.map(\.candidate.identifier),
            "fused order was not stable across identical runs"
        )
    }
}
