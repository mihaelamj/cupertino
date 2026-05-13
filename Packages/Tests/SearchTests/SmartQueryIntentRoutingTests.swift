import Foundation
@testable import Search
import SharedConstants
import SharedCore
import Testing

// Intent routing for cross-source smart query (#254).
//
// RRF treats every source equally, so a symbol-name query like `Task`
// fuses apple-docs' Swift Task struct (rank-1, score 1/61) with
// apple-archive's "Common Tasks in OS X" essay (rank-1, score 1/61) and
// the dictionary-order tiebreak buries the canonical answer.
//
// `Search.SmartQuery` now detects symbol-shaped queries and prunes the
// fetcher set to apple-docs / swift-evolution / packages before fan-out.
// Prose queries keep the original all-source path.

private actor CallRecorder {
    private(set) var called: [String] = []

    func record(_ source: String) {
        called.append(source)
    }

    func snapshot() -> [String] {
        called
    }
}

private struct RecordingMockFetcher: Search.CandidateFetcher {
    let sourceName: String
    let canned: [Search.SmartCandidate]
    let recorder: CallRecorder

    func fetch(question _: String, limit: Int) async throws -> [Search.SmartCandidate] {
        await recorder.record(sourceName)
        return Array(canned.prefix(limit))
    }
}

private func candidate(source: String, id: String) -> Search.SmartCandidate {
    Search.SmartCandidate(
        source: source,
        identifier: id,
        title: "title-\(id)",
        chunk: "chunk-\(id)",
        rawScore: 1.0
    )
}

private func makeFetchers(
    recorder: CallRecorder,
    sources: [String]
) -> [any Search.CandidateFetcher] {
    sources.map { source in
        RecordingMockFetcher(
            sourceName: source,
            canned: [candidate(source: source, id: "\(source)-1")],
            recorder: recorder
        )
    }
}

@Suite("Smart query intent routing (#254)")
struct SmartQueryIntentRoutingTests {
    private static let allSources: [String] = [
        Shared.Constants.SourcePrefix.appleDocs,
        Shared.Constants.SourcePrefix.appleArchive,
        Shared.Constants.SourcePrefix.swiftEvolution,
        Shared.Constants.SourcePrefix.swiftOrg,
        Shared.Constants.SourcePrefix.swiftBook,
        Shared.Constants.SourcePrefix.hig,
        Shared.Constants.SourcePrefix.packages,
    ]

    private static let expectedSymbolSources: Set<String> = [
        Shared.Constants.SourcePrefix.appleDocs,
        Shared.Constants.SourcePrefix.swiftEvolution,
        Shared.Constants.SourcePrefix.packages,
    ]

    // MARK: - isLikelySymbolQuery direct cases

    @Test(
        "isLikelySymbolQuery: canonical Apple type names classify as symbol",
        arguments: ["Task", "View", "URLSession", "Result", "Color", "String"]
    )
    func symbolQueriesClassified(query: String) {
        #expect(Search.SmartQuery.isLikelySymbolQuery(query))
    }

    @Test(
        "isLikelySymbolQuery: prose, lowercase, multi-token, dotted, and short stay non-symbol",
        arguments: [
            "how do I cancel an async operation",
            "swiftui view lifecycle",
            "view", // lowercase — ambiguous, fall through to prose
            "task",
            "URLSession.dataTask", // dotted member access — fall through
            "T", // single-letter — too sparse
            "",
            "  ",
            "@Observable", // attributes are not bare identifiers
        ]
    )
    func prosePathStays(query: String) {
        #expect(!Search.SmartQuery.isLikelySymbolQuery(query))
    }

    // MARK: - Routing behaviour through SmartQuery.answer

    @Test(
        "Symbol queries fan out only across apple-docs / swift-evolution / packages",
        arguments: ["Task", "View", "URLSession"]
    )
    func symbolQueryPrunesFetchers(query: String) async {
        let recorder = CallRecorder()
        let smart = Search.SmartQuery(
            fetchers: makeFetchers(recorder: recorder, sources: Self.allSources)
        )

        let result = await smart.answer(question: query, limit: 10)

        let calledSet = await Set(recorder.snapshot())
        #expect(calledSet == Self.expectedSymbolSources)
        #expect(Set(result.contributingSources) == Self.expectedSymbolSources)
    }

    @Test("Prose query still fans out across every configured source")
    func proseQueryKeepsAllSources() async {
        let recorder = CallRecorder()
        let smart = Search.SmartQuery(
            fetchers: makeFetchers(recorder: recorder, sources: Self.allSources)
        )

        let result = await smart.answer(
            question: "how do I cancel an async operation",
            limit: 10
        )

        let calledSet = await Set(recorder.snapshot())
        #expect(calledSet == Set(Self.allSources))
        #expect(Set(result.contributingSources) == Set(Self.allSources))
    }

    @Test("Source-scoped fall-through: caller passes only apple-archive — symbol query still runs it")
    func sourceScopedFallThrough() async {
        // CLI.Command.PackageSearch and `--source apple-archive` paths construct
        // SmartQuery with a single fetcher of a non-allowlisted source.
        // Intent routing must not silence that fetcher; otherwise scoped
        // queries return zero results.
        let recorder = CallRecorder()
        let smart = Search.SmartQuery(
            fetchers: makeFetchers(
                recorder: recorder,
                sources: [Shared.Constants.SourcePrefix.appleArchive]
            )
        )

        let result = await smart.answer(question: "Task", limit: 10)

        let called = await recorder.snapshot()
        #expect(called == [Shared.Constants.SourcePrefix.appleArchive])
        #expect(result.contributingSources == [Shared.Constants.SourcePrefix.appleArchive])
    }

    // MARK: - Authority-weighted RRF (#254 Option B)

    @Test("Symbol query with all 3 allowlisted sources tied at rank 1: apple-docs wins fused #1")
    func appleDocsWinsTieUnderWeightedRRF() async {
        // Each fetcher returns a single rank-1 candidate. Under unweighted
        // RRF all three would tie at 1/61 ≈ 0.0164 and dictionary order
        // would pick arbitrarily. Under #254 weighted RRF apple-docs (3.0)
        // beats swift-evolution and packages (1.5 each).
        let recorder = CallRecorder()
        let smart = Search.SmartQuery(
            fetchers: makeFetchers(
                recorder: recorder,
                sources: [
                    Shared.Constants.SourcePrefix.appleDocs,
                    Shared.Constants.SourcePrefix.swiftEvolution,
                    Shared.Constants.SourcePrefix.packages,
                ]
            )
        )

        let result = await smart.answer(question: "URLSession", limit: 5)

        #expect(result.candidates.first?.candidate.source == Shared.Constants.SourcePrefix.appleDocs)
        // apple-docs increment 3.0/61 ≈ 0.0492; the next-best (swift-evolution
        // or packages at 1.5/61 ≈ 0.0246) must score lower.
        let topScore = result.candidates.first?.score ?? 0
        let secondScore = result.candidates.dropFirst().first?.score ?? 0
        #expect(topScore > secondScore)
    }

    @Test("Prose query: apple-docs still wins ties via authority weighting")
    func appleDocsWinsProseTie() async {
        // Authority weighting applies on every fan-out, not just symbol
        // queries. For prose, when sources tie at rank 1, apple-docs still
        // wins. apple-archive and hig (weight 0.5) sit below baseline.
        let recorder = CallRecorder()
        let smart = Search.SmartQuery(
            fetchers: makeFetchers(
                recorder: recorder,
                sources: [
                    Shared.Constants.SourcePrefix.appleDocs,
                    Shared.Constants.SourcePrefix.appleArchive,
                    Shared.Constants.SourcePrefix.hig,
                ]
            )
        )

        let result = await smart.answer(
            question: "how do I cancel an async operation",
            limit: 5
        )

        #expect(result.candidates.first?.candidate.source == Shared.Constants.SourcePrefix.appleDocs)
    }

    @Test("Symbol query with mixed allowlisted + scoped fetchers keeps the allowlisted ones only")
    func mixedFetcherSetFiltersToAllowlist() async {
        let recorder = CallRecorder()
        let mixed: [String] = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftOrg,
        ]
        let smart = Search.SmartQuery(
            fetchers: makeFetchers(recorder: recorder, sources: mixed)
        )

        let result = await smart.answer(question: "URLSession", limit: 10)

        let calledSet = await Set(recorder.snapshot())
        #expect(calledSet == [Shared.Constants.SourcePrefix.appleDocs])
        #expect(result.contributingSources == [Shared.Constants.SourcePrefix.appleDocs])
    }
}
