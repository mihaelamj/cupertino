import Foundation
import Testing

// Enrichment #9 — Constraint Resolution.
//
// Apple's generic constraints, resolved from the cupertino-symbolgraphs
// corpus (AppleConstraintsKit -> apple-constraints.json) and attached to
// doc_symbols.generic_constraints at index time. Lets a query find symbols
// by the protocols their generic parameters are constrained to.

@Suite("Enrichment #9 — Constraint Resolution (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment09ConstraintResolutionTests {
    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("generic_constraints is populated on a substantial number of symbols")
    func constraintsPopulated() {
        guard let probe = docs() else { return }
        let found = probe.count("SELECT count(*) FROM doc_symbols WHERE generic_constraints IS NOT NULL AND generic_constraints<>''")
        #expect(found > 10000, "expected >10k constrained symbols, got \(found)")
    }

    @Test("Real Apple View constraints land on SwiftUI symbols")
    func viewConstraintsLand() {
        guard let probe = docs() else { return }
        // Many SwiftUI container symbols constrain a generic parameter to View.
        let found = probe.count("SELECT count(*) FROM doc_symbols WHERE generic_constraints LIKE '%View%'")
        #expect(found > 100, "expected >100 symbols constrained to View, got \(found)")
    }
}

/// The constraints as the AST query surface exposes them: search-generics
/// --constraint View finds symbols whose generic parameters require View.
@Suite("Enrichment #9 — Constraint Resolution via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment09ConstraintResolutionSearchTests {
    @Test("search-generics --constraint View returns symbols whose generics require View")
    func searchGenericsView() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let response = CupertinoCLI.searchGenerics(constraint: "View", ["--limit", "10"])
        #expect(response != nil, "search-generics returned no parseable response")
        let results = response?.results ?? []
        #expect(!results.isEmpty, "expected symbols constrained to View")
        // The command filters on the generic_constraints column and returns
        // the generic_params projection (formatting varies), so assert the
        // constraint surfaces in at least one result rather than all.
        let someMentionView = results.contains { ($0.genericParams ?? "").contains("View") }
        #expect(someMentionView, "at least one result's generic_params should reference View")
    }
}
