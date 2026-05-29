import Foundation
import Testing

// Enrichment #23 — Kind-Aware Reranking (#256, #610).
//
// Post-fusion heuristics on the main FTS search path: exact-title peers are
// tiebroken by symbol kind, and context-aware kind boosting surfaces the
// canonical declaration over incidental mentions. The canonical example is
// "Task": raw BM25 buries the Swift Task struct (its title carries the
// " | Apple Developer Documentation" suffix), but the rerank pulls it to
// #1 over property/method pages that merely mention "task". Query-time
// only.

@Suite("Enrichment #23 — Kind-Aware Reranking via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment23KindAwareRerankingTests {
    @Test("The canonical Task struct is reranked to #1 over incidental 'task' mentions")
    func taskCanonicalFirst() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let results = CupertinoCLI.searchDocs("Task", ["--source", "apple-docs", "--limit", "3"])
        #expect(
            results.first?.uri == "apple-docs://swift/task",
            "Task should rerank the canonical Swift struct to #1, got \(String(describing: results.first?.uri))"
        )
    }

    @Test("A type query lands its canonical page first, not a member page")
    func canonicalOverMember() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        // URLSession the class should beat urlsession(_:...) delegate methods.
        let results = CupertinoCLI.searchDocs("URLSession", ["--source", "apple-docs", "--limit", "3"])
        #expect(
            results.first?.uri == "apple-docs://foundation/urlsession",
            "URLSession class page should rerank to #1, got \(String(describing: results.first?.uri))"
        )
    }
}
