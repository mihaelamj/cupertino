import Foundation
import Testing

// Enrichment #24 — AST Boilerplate Demotion (#177).
//
// The 4 AST symbol-query commands (search-symbols, search-property-wrappers,
// search-concurrency, search-conformances) share a signal-rank ORDER BY
// that deprioritizes (does not exclude) auto-synthesized Equatable /
// Hashable / Comparable conformance members and operator overloads. Before
// the fix a query like "task" surfaced `==` / `<` operator overloads ahead
// of the real Task type. Query-time only.

@Suite("Enrichment #24 — AST Boilerplate Demotion via cupertino search-symbols", .enabled(if: CupertinoCLI.available))
struct Enrichment24ASTBoilerplateDemotionTests {
    @Test("search-symbols 'task' surfaces the real Task type, not synthesized operators")
    func taskNotOperators() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let response = CupertinoCLI.searchSymbols(query: "task", ["--limit", "8"])
        let results = response?.results ?? []
        #expect(!results.isEmpty, "search-symbols returned nothing for 'task'")
        // The top result should be a real Task symbol, not an operator overload.
        #expect(
            results.first?.symbolName.lowercased() == "task",
            "top symbol should be Task, got \(String(describing: results.first?.symbolName))"
        )
        #expect(results.first?.symbolKind != "operator", "top symbol should not be an operator")
    }

    @Test("Synthesized '==' operator boilerplate is demoted out of the top results")
    func equalsOperatorDemoted() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let response = CupertinoCLI.searchSymbols(query: "task", ["--limit", "8"])
        let topNames = (response?.results ?? []).prefix(8).map(\.symbolName)
        #expect(!topNames.contains("=="), "synthesized '==' should be demoted below the top results, got \(topNames)")
    }
}
