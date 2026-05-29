import Foundation
import Testing

// Enrichment #22 — Intent Routing (#254).
//
// Query-intent classification prunes the fetcher set and applies per-source
// authority weights so a prose-heavy source's rank-1 result does not fuse
// ahead of the canonical API page. Apple-docs carries the highest authority
// weight (3.0), so an API-shaped query should be topped by apple-docs even
// when several sources contribute. Query-time only.

@Suite("Enrichment #22 — Intent Routing via cupertino search", .enabled(if: CupertinoCLI.available), .serialized)
struct Enrichment22IntentRoutingTests {
    @Test("An API-shaped query is topped by apple-docs authority in the fused list")
    func appleDocsAuthorityWins() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let response = CupertinoCLI.searchFanout("URLSession", ["--limit", "5"])
        #expect(response != nil, "fan-out returned no parseable response")
        let topSource = response?.candidates.first?.source
        #expect(
            topSource == "apple-docs",
            "apple-docs authority weight should top an API query, got top source \(String(describing: topSource))"
        )
    }

    @Test("apple-docs participates in the fan-out for an API query")
    func appleDocsContributes() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let response = CupertinoCLI.searchFanout("URLSession", ["--limit", "5"])
        #expect(response?.contributingSources.contains("apple-docs") == true)
    }
}
