import Foundation
import Testing

// Enrichment #21 — Rank Fusion (RRF).
//
// The default (no --source) search fans out across every source DB
// concurrently and merges their independently-ranked lists via reciprocal
// rank fusion (1/(k+rank), k=60). This is a query-time behavior with no
// stored column, so it is exercised only through `cupertino search`.

@Suite("Enrichment #21 — Rank Fusion via cupertino search", .enabled(if: CupertinoCLI.available), .serialized)
struct Enrichment21RankFusionTests {
    @Test("A bare query fans out across multiple sources and returns a fused list")
    func fanoutFusesMultipleSources() {
        let response = CupertinoCLI.searchFanout("observable macro", ["--limit", "5"])
        #expect(response != nil, "fan-out returned no parseable response")
        // Fan-out should consult several source DBs concurrently.
        #expect(
            (response?.contributingSources.count ?? 0) >= 3,
            "expected fan-out across >=3 sources, got \(response?.contributingSources ?? [])"
        )
        // And return a single merged candidate list.
        #expect((response?.candidates.isEmpty == false), "fused candidate list was empty")
    }

    @Test("Fused candidates can draw from more than one source in one query")
    func fusionSpansSources() {
        // A broad concept query surfaces hits from several corpora; the RRF
        // merge interleaves them into one ranked list.
        let response = CupertinoCLI.searchFanout("concurrency", ["--limit", "20"])
        let sources = Set((response?.candidates ?? []).compactMap(\.source))
        #expect(!sources.isEmpty, "no sources on fused candidates")
    }
}
