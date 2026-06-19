import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import Services
import ServicesModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #1286 — the unified (MCP/desktop) fan-out routes each docs source to its own per-source DB

///
/// Regression guard for #1286: testing the installed corpus through the MCP
/// `serve` path showed the desktop searched only 3 of 8 sources. Root cause:
/// `Services.UnifiedSearchService.searchAll` issues a `searchSource(source:)`
/// per docs source but routed EVERY one through the single injected
/// `searchIndex` (the apple-docs primary DB). On a per-source-DB bundle (#1036)
/// the apple-docs DB holds only apple-docs rows, so hig / swift-evolution /
/// etc. came back empty even though their DBs are installed. The CLI fans
/// across all of them; the MCP/desktop path did not.
///
/// Post-fix `UnifiedSearchService` routes each source to its own per-source
/// index via `docsIndexBySource`. This test wires two single-source indexes
/// (apple-docs + hig, the per-source-split reality) and asserts a unified
/// search returns BOTH the apple-docs and the hig buckets. Proven non-vacuous:
/// with the map empty (the pre-#1286 single-index wiring) the hig bucket is
/// empty.
@Suite("#1286 — unified fan-out searches every wired per-source docs DB")
struct Issue1286UnifiedSearchPerSourceFanoutTests {
    /// A real single-source docs index: a temp DB with one indexed doc tagged
    /// `source`, whose title/content match `query`. Mirrors the per-source-DB
    /// reality (each docs DB holds only its own source's rows).
    private func makeSingleSourceIndex(source: String, uri: String, query: String) async throws -> Search.Index {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("fanout-1286-\(source)-\(UUID().uuidString).db")
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: uri,
            source: source,
            framework: nil,
            title: "\(query.capitalized) reference (\(source))",
            content: "Guidance about \(query) from the \(source) source.",
            filePath: "/tmp/\(source)",
            contentHash: "h-\(source)",
            lastCrawled: Date(timeIntervalSince1970: 1700000000)
        ))
        return index
    }

    @Test("unified search returns results from a non-primary docs source (hig) when its DB is wired")
    func unifiedFanoutSpansPerSourceDocsDBs() async throws {
        let query = "buttons"
        let appleDocs = try await makeSingleSourceIndex(
            source: Shared.Constants.SourcePrefix.appleDocs,
            uri: "apple-docs://uikit/uibutton",
            query: query
        )
        let hig = try await makeSingleSourceIndex(
            source: Shared.Constants.SourcePrefix.hig,
            uri: "hig://components/buttons",
            query: query
        )
        defer { Task { await appleDocs.disconnect(); await hig.disconnect() } }

        // The serve/desktop composition: the apple-docs primary index PLUS the
        // per-source docs index map (#1286).
        let unified = Services.UnifiedSearchService(
            searchIndex: appleDocs,
            sampleDatabase: nil,
            packagesSearcher: nil,
            docsIndexBySource: [
                Shared.Constants.SourcePrefix.appleDocs: appleDocs,
                Shared.Constants.SourcePrefix.hig: hig,
            ]
        )
        let input = await unified.searchAll(
            query: query,
            framework: nil,
            limit: 10,
            availableSources: [Shared.Constants.SourcePrefix.appleDocs, Shared.Constants.SourcePrefix.hig]
        )

        #expect(!input.docResults.isEmpty, "apple-docs bucket empty")
        #expect(!input.higResults.isEmpty, "hig bucket empty — the non-primary per-source DB was not searched (#1286)")
    }

    @Test("contrast: without the per-source map (legacy single-index wiring), the hig bucket is empty")
    func legacySingleIndexMissesNonPrimarySource() async throws {
        let query = "buttons"
        let appleDocs = try await makeSingleSourceIndex(
            source: Shared.Constants.SourcePrefix.appleDocs,
            uri: "apple-docs://uikit/uibutton",
            query: query
        )
        defer { Task { await appleDocs.disconnect() } }

        // Pre-#1286 wiring: only the apple-docs primary index, no per-source map.
        let unified = Services.UnifiedSearchService(searchIndex: appleDocs, sampleDatabase: nil)
        let input = await unified.searchAll(
            query: query,
            framework: nil,
            limit: 10,
            availableSources: [Shared.Constants.SourcePrefix.appleDocs, Shared.Constants.SourcePrefix.hig]
        )

        #expect(!input.docResults.isEmpty)
        // The bug this fix closes: the apple-docs DB has no hig rows.
        #expect(input.higResults.isEmpty)
    }
}

// MARK: - #1286 — specific-source (scoped) docs search routes to the per-source DB

/// The specific-source MCP routes (`search --source hig`, `list_documents
/// source=swift-evolution`, `list_children`) go through
/// `Services.DocsSearchService`, which pre-#1286 always queried the single
/// apple-docs primary index, so a scoped search for a non-apple-docs source
/// returned 0 even though its DB is installed. `DocsSearchService` now routes
/// source-scoped operations to the per-source index map. This pins that a
/// `search` scoped to a non-primary source returns that source's rows, and
/// that the legacy (empty-map) wiring returns none.
@Suite("#1286 — scoped DocsSearchService search routes to the per-source DB")
struct Issue1286ScopedDocsSearchRoutingTests {
    private func makeIndex(source: String, uri: String, query: String) async throws -> Search.Index {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("scoped-1286-\(source)-\(UUID().uuidString).db")
        let index = try await Search.Index(
            dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty
        )
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: uri, source: source, framework: nil,
            title: "\(query.capitalized) (\(source))",
            content: "Doc about \(query) in \(source).",
            filePath: "/tmp/\(source)", contentHash: "h-\(source)",
            lastCrawled: Date(timeIntervalSince1970: 1700000000)
        ))
        return index
    }

    private func scopedQuery(_ text: String, source: String) -> Services.SearchQuery {
        Services.SearchQuery(
            text: text, source: source, framework: nil, language: nil, limit: 10,
            includeArchive: false, minimumiOS: nil, minimumMacOS: nil, minimumTvOS: nil,
            minimumWatchOS: nil, minimumVisionOS: nil, minimumSwift: nil
        )
    }

    @Test("scoped search for a non-primary source returns its rows when the per-source DB is mapped")
    func scopedSearchRoutesToPerSourceDB() async throws {
        let appleDocs = try await makeIndex(source: Shared.Constants.SourcePrefix.appleDocs, uri: "apple-docs://uikit/uibutton", query: "buttons")
        let hig = try await makeIndex(source: Shared.Constants.SourcePrefix.hig, uri: "hig://general/buttons", query: "buttons")
        defer { Task { await appleDocs.disconnect(); await hig.disconnect() } }

        let service = Services.DocsSearchService(
            database: appleDocs,
            docsIndexBySource: [
                Shared.Constants.SourcePrefix.appleDocs: appleDocs,
                Shared.Constants.SourcePrefix.hig: hig,
            ]
        )
        let higResults = try await service.search(scopedQuery("buttons", source: Shared.Constants.SourcePrefix.hig))
        #expect(!higResults.isEmpty, "scoped hig search returned nothing despite the hig DB being mapped (#1286)")
    }

    @Test("contrast: legacy single-index wiring returns nothing for a non-primary scoped source")
    func legacyScopedSearchReturnsEmpty() async throws {
        let appleDocs = try await makeIndex(source: Shared.Constants.SourcePrefix.appleDocs, uri: "apple-docs://uikit/uibutton", query: "buttons")
        defer { Task { await appleDocs.disconnect() } }

        let service = Services.DocsSearchService(database: appleDocs) // no per-source map
        let higResults = try await service.search(scopedQuery("buttons", source: Shared.Constants.SourcePrefix.hig))
        #expect(higResults.isEmpty)
    }
}
