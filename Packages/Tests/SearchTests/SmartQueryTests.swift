import Foundation
@testable import Search
import Testing

// Reciprocal rank fusion (#192 section E4). Covered with a deterministic
// in-memory `MockFetcher` so the fusion math is guarded independently of
// SQLite + FTS behaviour.

private struct MockFetcher: Search.CandidateFetcher {
    let sourceName: String
    let canned: [Search.SmartCandidate]
    let fail: Bool

    init(sourceName: String, canned: [Search.SmartCandidate], fail: Bool = false) {
        self.sourceName = sourceName
        self.canned = canned
        self.fail = fail
    }

    func fetch(question: String, limit: Int) async throws -> [Search.SmartCandidate] {
        if fail {
            struct Oops: Error {}
            throw Oops()
        }
        return Array(canned.prefix(limit))
    }
}

private func candidate(source: String, id: String, title: String = "t", rawScore: Double = 0) -> Search.SmartCandidate {
    Search.SmartCandidate(
        source: source,
        identifier: id,
        title: title,
        chunk: "chunk for \(id)",
        rawScore: rawScore
    )
}

@Suite("Search.SmartQuery (#192 E4)")
struct SmartQueryTests {
    @Test("Single fetcher: order preserved, scores descend, fetcher listed as contributing")
    func singleFetcher() async {
        let fetcher = MockFetcher(
            sourceName: "packages",
            canned: [
                candidate(source: "packages", id: "a"),
                candidate(source: "packages", id: "b"),
                candidate(source: "packages", id: "c"),
            ]
        )
        let smart = Search.SmartQuery(fetchers: [fetcher])

        let result = await smart.answer(question: "anything", limit: 5)

        #expect(result.candidates.map(\.candidate.identifier) == ["a", "b", "c"])
        #expect(result.candidates.map(\.score) == result.candidates.map(\.score).sorted(by: >))
        #expect(result.contributingSources == ["packages"])
    }

    @Test("Two fetchers: RRF interleaves top hits")
    func twoFetchersInterleave() async {
        // With `k=60`, rank-1 from each source gets 1/61 ≈ 0.0164, and they
        // should tie-or-win over rank-2 hits (1/62 ≈ 0.0161). The fused top
        // two results should include one rank-1 hit from each source.
        let packages = MockFetcher(sourceName: "packages", canned: [
            candidate(source: "packages", id: "pkg-1"),
            candidate(source: "packages", id: "pkg-2"),
        ])
        let docs = MockFetcher(sourceName: "apple-docs", canned: [
            candidate(source: "apple-docs", id: "doc-1"),
            candidate(source: "apple-docs", id: "doc-2"),
        ])
        let smart = Search.SmartQuery(fetchers: [packages, docs])

        let result = await smart.answer(question: "q", limit: 4)

        let top2 = Set(result.candidates.prefix(2).map(\.candidate.identifier))
        #expect(top2 == Set(["pkg-1", "doc-1"]))
        #expect(Set(result.contributingSources) == Set(["packages", "apple-docs"]))
    }

    @Test("Failing fetcher is skipped; successful fetcher still contributes")
    func failingFetcherSkipped() async {
        let dead = MockFetcher(sourceName: "apple-docs", canned: [], fail: true)
        let alive = MockFetcher(sourceName: "packages", canned: [
            candidate(source: "packages", id: "pkg-1"),
        ])
        let smart = Search.SmartQuery(fetchers: [dead, alive])

        let result = await smart.answer(question: "q", limit: 5)

        #expect(result.candidates.map(\.candidate.identifier) == ["pkg-1"])
        #expect(result.contributingSources == ["packages"])
    }

    @Test("No fetchers produce candidates: result is empty and contributingSources is empty")
    func emptyResult() async {
        let empty = MockFetcher(sourceName: "apple-docs", canned: [])
        let smart = Search.SmartQuery(fetchers: [empty])

        let result = await smart.answer(question: "q", limit: 5)

        #expect(result.candidates.isEmpty)
        #expect(result.contributingSources.isEmpty)
    }

    @Test("perFetcherLimit caps each source before fusion")
    func perFetcherLimitCaps() async {
        // A source that returns 50 candidates must only contribute `perFetcherLimit`
        // of them to the fusion, otherwise a noisy source can drown out a
        // high-quality single hit from another source.
        let noisy = MockFetcher(
            sourceName: "noisy",
            canned: (1...50).map { candidate(source: "noisy", id: "noisy-\($0)") }
        )
        let smart = Search.SmartQuery(fetchers: [noisy])

        let result = await smart.answer(question: "q", limit: 100, perFetcherLimit: 3)

        #expect(result.candidates.count == 3)
        #expect(result.candidates.map(\.candidate.identifier) == ["noisy-1", "noisy-2", "noisy-3"])
    }

    @Test("Rank 1 across both sources has identical fused score")
    func rankOnesTie() async {
        // Since both rank-1 hits get 1/(60+1), their fused scores must be equal.
        let fetcherA = MockFetcher(sourceName: "a", canned: [candidate(source: "a", id: "a-1")])
        let fetcherB = MockFetcher(sourceName: "b", canned: [candidate(source: "b", id: "b-1")])
        let smart = Search.SmartQuery(fetchers: [fetcherA, fetcherB])

        let result = await smart.answer(question: "q", limit: 10)

        #expect(result.candidates.count == 2)
        #expect(result.candidates[0].score == result.candidates[1].score)
    }
}
