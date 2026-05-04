import Foundation
@testable import Search
import Shared
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
        // PackageSearchCommand and `--source apple-archive` paths construct
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
