import Foundation
import Testing

// Enrichment #2 — Symbol Field Boosting.
//
// AST-extracted symbol names are denormalized into dedicated FTS fields
// (`symbols`, `symbol_components`) so exact symbol matches rank above
// prose. The boost itself is the BM25F weight vector applied at query
// time: symbols = 5.0, symbol_components = 1.5 (vs content = 1.0).
//
// This battery proves the fields are populated AND that the weight
// actually reorders results: a symbol query lands its canonical page
// first, and zeroing the symbols weight changes the winner.

@Suite("Enrichment #2 — Symbol Field Boosting (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment02SymbolFieldBoostingTests {
    // Mirrors the production weight vector in
    // SearchSQLite/Search.Index.Search.swift (docs_fts columns in order:
    // uri, source, framework, language, title, content, summary,
    // symbols=5.0, symbol_components=1.5).
    static let weights = "1.0,1.0,2.0,1.0,10.0,1.0,3.0,5.0,1.5"
    static let weightsSymbolsZeroed = "1.0,1.0,2.0,1.0,10.0,1.0,3.0,0.0,0.0"

    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("symbols + symbol_components are columns on docs_fts")
    func columnsExist() {
        guard let probe = docs() else { return }
        let sql = probe.createSQL("docs_fts") ?? ""
        #expect(sql.contains("symbols"))
        #expect(sql.contains("symbol_components"))
    }

    @Test("symbols column is populated on a meaningful fraction of rows")
    func symbolsPopulated() {
        guard let probe = docs() else { return }
        let found = probe.count("SELECT count(*) FROM docs_fts WHERE symbols IS NOT NULL AND symbols <> ''")
        #expect(found > 100000, "expected >100k symbol-bearing rows, got \(found)")
    }

    @Test("symbol_components column is populated (CamelCase splits)")
    func componentsPopulated() {
        guard let probe = docs() else { return }
        let found = probe.count("SELECT count(*) FROM docs_fts WHERE symbol_components IS NOT NULL AND symbol_components <> ''")
        #expect(found > 100000, "expected >100k symbol_components rows, got \(found)")
    }

    @Test("A symbol query ranks its canonical symbol page first")
    func symbolQueryRanksCanonicalFirst() {
        guard let probe = docs() else { return }
        let topURI = probe.text(
            "SELECT uri FROM docs_fts WHERE docs_fts MATCH 'lazyvgrid' ORDER BY bm25(docs_fts, \(Self.weights)) LIMIT 1"
        ) ?? ""
        #expect(topURI.lowercased().contains("lazyvgrid"), "LazyVGrid query top-1 should be the canonical page, got \(topURI)")
        let topSymbols = probe.text(
            "SELECT symbols FROM docs_fts WHERE docs_fts MATCH 'lazyvgrid' ORDER BY bm25(docs_fts, \(Self.weights)) LIMIT 1"
        ) ?? ""
        #expect(topSymbols.lowercased().contains("lazyvgrid"), "canonical page should carry LazyVGrid in its symbols column")
    }

    @Test("Zeroing the symbols weight changes the top result (boost is live)")
    func boostChangesRanking() {
        guard let probe = docs() else { return }
        let prod = probe.text(
            "SELECT uri FROM docs_fts WHERE docs_fts MATCH 'grid' ORDER BY bm25(docs_fts, \(Self.weights)) LIMIT 1"
        ) ?? "A"
        let zeroed = probe.text(
            "SELECT uri FROM docs_fts WHERE docs_fts MATCH 'grid' ORDER BY bm25(docs_fts, \(Self.weightsSymbolsZeroed)) LIMIT 1"
        ) ?? "B"
        #expect(prod != zeroed, "zeroing the symbols weight should change top-1 for 'grid'; prod=\(prod) zeroed=\(zeroed)")
    }
}

/// The boost as the production pipeline applies it: a bare symbol query
/// should land its canonical page first and expose the matched symbol.
@Suite("Enrichment #2 — Symbol Field Boosting via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment02SymbolFieldBoostingSearchTests {
    @Test("LazyVGrid ranks the canonical struct page first with the symbol matched")
    func lazyVGridCanonicalFirst() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let results = CupertinoCLI.searchDocs("LazyVGrid", ["--source", "apple-docs", "--limit", "3"])
        #expect(!results.isEmpty, "expected results for LazyVGrid")
        guard let top = results.first else { return }
        #expect(top.uri.lowercased().contains("lazyvgrid"), "top result should be canonical LazyVGrid page, got \(top.uri)")
        let matched = (top.matchedSymbols ?? []).contains { $0.name.lowercased() == "lazyvgrid" }
        #expect(matched, "top result should expose LazyVGrid in matchedSymbols")
    }
}
