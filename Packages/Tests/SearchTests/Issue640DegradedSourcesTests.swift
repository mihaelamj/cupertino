import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import Testing

/// Regression suite for [#640](https://github.com/mihaelamj/cupertino/issues/640).
///
/// Pre-fix, `Search.SmartQuery.answer` swallowed every per-fetcher
/// error into an empty result set so one dead source couldn't take the
/// whole fan-out down. That was right for transient errors (network
/// blips, lock contention) but wrong for configuration errors (schema
/// mismatch, DB unopenable) — those are permanent until the user acts,
/// and AI agents reading the MCP response had no way to distinguish
/// "no apple-docs match for the query" from "apple-docs.db is
/// unopenable".
///
/// Post-fix:
///
/// 1. `Search.SmartQuery.classifyDegradation(_:)` matches the error
///    message against known configuration-error patterns ("schema
///    version", "unable to open database", "file is not a database")
///    and returns a human-readable reason string when it hits.
/// 2. `Search.SmartQuery.answer` aggregates degraded sources into the
///    `SmartResult.degradedSources` channel. Transient errors still
///    collapse silently.
/// 3. CLI text/markdown/JSON formatters and the MCP markdown response
///    body prepend a `⚠ Schema mismatch` warning when
///    `degradedSources` is non-empty.
@Suite("#640 SmartQuery surfaces degraded sources", .serialized)
struct Issue640DegradedSourcesTests {
    // MARK: - Classification

    @Test(
        "classifyDegradation tags schema-mismatch errors with the `cupertino setup` hint",
        arguments: [
            "SQLite error: Database schema version 14 is newer than supported version 13",
            "Database schema version 13 requires migration to version 14",
            "schema version mismatch",
        ]
    )
    func classifiesSchemaMismatch(message: String) {
        let error = Search.Error.sqliteError(message)
        let reason = Search.SmartQuery.classifyDegradation(error)
        try? #require(reason != nil, "schema-mismatch should be classified as configuration error")
        #expect(reason?.contains("schema mismatch") == true)
        #expect(reason?.contains("cupertino setup") == true)
    }

    @Test(
        "classifyDegradation tags DB-unopenable errors with a path-check hint",
        arguments: [
            "unable to open database file",
            "file is not a database",
        ]
    )
    func classifiesUnopenableDB(message: String) {
        let error = Search.Error.sqliteError(message)
        let reason = Search.SmartQuery.classifyDegradation(error)
        try? #require(reason != nil)
        #expect(reason?.contains("database unopenable") == true)
    }

    @Test("classifyDegradation returns nil for transient errors (no false-positive warnings)")
    func classifiesTransientAsNil() {
        // "no results" / generic prepare-failed / arbitrary fetcher
        // errors are NOT configuration problems — they should stay in
        // the silent-swallow path so the warning channel keeps a clean
        // signal-to-noise ratio.
        #expect(Search.SmartQuery.classifyDegradation(Search.Error.invalidQuery("Query cannot be empty")) == nil)
        #expect(Search.SmartQuery.classifyDegradation(Search.Error.prepareFailed("syntax error near WHERE")) == nil)
        #expect(Search.SmartQuery.classifyDegradation(Search.Error.databaseNotInitialized) == nil)
    }

    // MARK: - Fan-out plumbing

    /// Minimal fetcher that throws a configurable error on `fetch`.
    /// Used to exercise the SmartQuery degradation aggregation path
    /// without standing up a real DB.
    private struct FailingFetcher: Search.CandidateFetcher {
        let sourceName: String
        let error: any Swift.Error
        func fetch(question _: String, limit _: Int) async throws -> [Search.SmartCandidate] {
            throw error
        }
    }

    /// Minimal fetcher that returns a single happy-path candidate.
    private struct OKFetcher: Search.CandidateFetcher {
        let sourceName: String
        func fetch(question _: String, limit _: Int) async throws -> [Search.SmartCandidate] {
            [
                Search.SmartCandidate(
                    source: sourceName,
                    identifier: "\(sourceName)://ok",
                    title: "ok",
                    chunk: "stub",
                    rawScore: 1.0,
                    kind: nil,
                    metadata: [:]
                ),
            ]
        }
    }

    @Test("SmartQuery.answer aggregates schema-mismatch errors into degradedSources")
    func aggregatesSchemaMismatch() async {
        let fetchers: [any Search.CandidateFetcher] = [
            FailingFetcher(
                sourceName: Shared.Constants.SourcePrefix.appleDocs,
                error: Search.Error.sqliteError("Database schema version 14 is newer than supported version 13")
            ),
            OKFetcher(sourceName: Shared.Constants.SourcePrefix.samples),
        ]
        // Use a multi-word prose query so `routeFetchers` doesn't
        // strip samples as a non-symbol source (symbol queries narrow
        // the fan-out to symbol-preferred sources — apple-docs / swift-
        // evolution / packages). For this test we want both sources to
        // run through the fan-out.
        let result = await Search.SmartQuery(fetchers: fetchers).answer(question: "how do I use sessions")

        let names = result.degradedSources.map(\.name)
        #expect(names == [Shared.Constants.SourcePrefix.appleDocs])
        let reason = result.degradedSources.first?.reason ?? ""
        #expect(reason.contains("cupertino setup"))

        // The happy-path source still contributes — fan-out resilience is preserved.
        #expect(result.contributingSources.contains(Shared.Constants.SourcePrefix.samples))
    }

    @Test("SmartQuery.answer does NOT surface transient errors (they keep the silent-swallow path)")
    func transientErrorsStaySilent() async {
        // Non-configuration error — should land in `contributingSources`
        // as a no-show (empty result) but NOT in `degradedSources`.
        let fetchers: [any Search.CandidateFetcher] = [
            FailingFetcher(
                sourceName: Shared.Constants.SourcePrefix.swiftEvolution,
                error: Search.Error.invalidQuery("test transient")
            ),
            OKFetcher(sourceName: Shared.Constants.SourcePrefix.samples),
        ]
        let result = await Search.SmartQuery(fetchers: fetchers).answer(question: "anything")

        #expect(
            result.degradedSources.isEmpty,
            "transient errors must not pollute degradedSources; got \(result.degradedSources)"
        )
    }

    @Test("SmartQuery.answer aggregates degradation across multiple sources")
    func aggregatesMultipleSources() async {
        let fetchers: [any Search.CandidateFetcher] = [
            FailingFetcher(
                sourceName: Shared.Constants.SourcePrefix.appleDocs,
                error: Search.Error.sqliteError("schema version mismatch")
            ),
            FailingFetcher(
                sourceName: Shared.Constants.SourcePrefix.hig,
                error: Search.Error.sqliteError("schema version mismatch")
            ),
            OKFetcher(sourceName: Shared.Constants.SourcePrefix.samples),
        ]
        let result = await Search.SmartQuery(fetchers: fetchers).answer(question: "anything")

        let names = Set(result.degradedSources.map(\.name))
        #expect(names == Set([
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
        ]))
    }

    @Test("SmartResult.degradedSources defaults to empty on the happy path (no shape regression)")
    func happyPathLeavesDegradedEmpty() async {
        let fetchers: [any Search.CandidateFetcher] = [
            OKFetcher(sourceName: Shared.Constants.SourcePrefix.appleDocs),
            OKFetcher(sourceName: Shared.Constants.SourcePrefix.samples),
        ]
        let result = await Search.SmartQuery(fetchers: fetchers).answer(question: "ok")
        #expect(result.degradedSources.isEmpty)
        #expect(result.contributingSources.count == 2)
    }
}
