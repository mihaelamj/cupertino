import Foundation
import Testing

// Enrichment #14 — Structured Projection.
//
// DocC JSON fields lifted into queryable columns on docs_structured
// (declaration, overview, abstract, platforms, conforms_to, ...). This is
// what feeds the title/summary a search result shows, so the CLI layer
// asserts those projected fields surface through `cupertino search`.

@Suite("Enrichment #14 — Structured Projection (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment14StructuredProjectionTests {
    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("docs_structured is populated for the whole corpus")
    func populated() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM docs_structured") > 100000)
    }

    @Test("Projected fields (declaration, platforms) are lifted into columns")
    func fieldsLifted() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM docs_structured WHERE declaration IS NOT NULL AND declaration<>''") > 100000)
        #expect(probe.count("SELECT count(*) FROM docs_structured WHERE platforms IS NOT NULL AND platforms NOT IN ('', '[]')") > 100000)
    }

    @Test("A known type page projects its declaration")
    func knownPageProjection() {
        guard let probe = docs() else { return }
        let declaration = probe.text("SELECT declaration FROM docs_structured WHERE uri='apple-docs://swiftui/lazyvgrid'") ?? ""
        #expect(declaration.contains("LazyVGrid"), "LazyVGrid page should project a declaration naming the type, got '\(declaration.prefix(80))'")
    }
}

/// The projection as the pipeline surfaces it: search results carry the
/// summary lifted from the structured doc.
@Suite("Enrichment #14 — Structured Projection via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment14StructuredProjectionSearchTests {
    @Test("Search results carry a non-empty summary from the structured projection")
    func summarySurfaces() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let results = CupertinoCLI.searchDocs("LazyVGrid", ["--source", "apple-docs", "--limit", "1"])
        let summary = results.first?.summary ?? ""
        #expect(!summary.isEmpty, "top result should carry a summary projected from docs_structured")
    }
}
