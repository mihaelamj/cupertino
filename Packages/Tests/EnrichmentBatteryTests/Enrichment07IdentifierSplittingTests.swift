import Foundation
import Testing

// Enrichment #7 — Identifier Splitting.
//
// Acronym-aware CamelCase tokenization of symbol names into the
// symbol_components FTS field (LazyVGrid -> "Lazy VGrid Grid",
// URLSession -> "URL Session"). Lets a fragment query ("grid", "decoder")
// match a compound type it is buried inside.

@Suite("Enrichment #7 — Identifier Splitting (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment07IdentifierSplittingTests {
    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("symbol_components is populated across the corpus")
    func componentsPopulated() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM docs_fts WHERE symbol_components IS NOT NULL AND symbol_components<>''") > 100000)
    }

    @Test("A compound name splits into its CamelCase components")
    func lazyVGridSplits() {
        guard let probe = docs() else { return }
        let components = probe.text(
            "SELECT symbol_components FROM docs_fts WHERE uri='apple-docs://swiftui/lazyvgrid'"
        ) ?? ""
        // Acronym-aware: keeps the VGrid run AND extracts the Grid tail.
        #expect(components.contains("Grid"), "LazyVGrid components should include Grid, got '\(components)'")
        #expect(components.contains("Lazy"), "LazyVGrid components should include Lazy, got '\(components)'")
    }

    @Test("The split tokens are searchable via FTS MATCH on symbol_components")
    func fragmentMatchesViaComponents() {
        guard let probe = docs() else { return }
        // "Grid" as a standalone token matches LazyVGrid's components row.
        let hits = probe.count(
            "SELECT count(*) FROM docs_fts WHERE symbol_components MATCH 'Grid' AND uri='apple-docs://swiftui/lazyvgrid'"
        )
        #expect(hits == 1, "symbol_components MATCH 'Grid' should hit the LazyVGrid row")
    }
}

/// The split as the pipeline uses it: a bare fragment finds the compound
/// types that embed it.
@Suite("Enrichment #7 — Identifier Splitting via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment07IdentifierSplittingSearchTests {
    @Test("Fragment 'Decoder' surfaces compound types like JSONDecoder")
    func fragmentSurfacesCompound() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let results = CupertinoCLI.searchDocs("Decoder", ["--source", "apple-docs", "--limit", "10"])
        let hasJSONDecoder = results.contains { $0.uri.lowercased().hasSuffix("/jsondecoder") }
        #expect(hasJSONDecoder, "fragment 'Decoder' should surface JSONDecoder via symbol_components; got \(results.map(\.uri))")
    }
}
