import Foundation
import Testing

// Enrichment #11: Framework Aliasing.
//
// A framework_aliases table routes bare acronyms / informal names to their
// canonical framework root (bluetooth -> CoreBluetooth, nfc -> CoreNFC,
// ...). The 22 hand-curated aliases are attached by SynonymsPass via an
// UPDATE keyed on the `framework` column.
//
// SNAPSHOT STATUS (2026-06-02): the framework='docs' misbuild is FIXED, and
// SynonymsPass now attaches synonyms. apple-documentation.db is rebuilt with
// `framework` derived from the document URL, so real identifiers dominate.
// Search-level aliasing works (a bare 'bluetooth' query routes to
// CoreBluetooth). The #1143 upsert fix plus re-enrichment populated
// `framework_aliases.synonyms`: the snapshot now has 340 alias rows with 22
// non-empty synonyms (e.g. corewlan -> wifi,wlan), so the `synonymsAttached`
// DB-column test is re-enabled (#1132).

@Suite("Enrichment #11: Framework Aliasing (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment11FrameworkAliasingTests {
    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("framework_aliases table exists with the expected columns")
    func tableShape() {
        guard let probe = docs() else { return }
        #expect(probe.hasTable("framework_aliases"))
        let cols = Set(probe.tableColumns("framework_aliases"))
        for col in ["identifier", "import_name", "display_name", "synonyms"] {
            #expect(cols.contains(col), "framework_aliases missing \(col)")
        }
    }

    @Test("framework column is correctly built: framework='docs' does not dominate")
    func frameworkColumnIsCorrectlyBuilt() {
        guard let probe = docs() else { return }
        // Regression guard for the framework='docs' misbuild (indexing with
        // --docs-dir one level too high). The fix derives `framework` from
        // the document URL; this fails if that regresses.
        let docsFramework = probe.count("SELECT count(*) FROM docs_metadata WHERE framework='docs'")
        let total = probe.count("SELECT count(*) FROM docs_metadata")
        #expect(
            docsFramework <= total / 2,
            """
            framework='docs' dominates (\(docsFramework)/\(total)); \
            the misbuild regressed, rebuild with --docs-dir .../docs
            """
        )
    }

    @Test("The 22 framework synonyms are attached")
    func synonymsAttached() {
        guard let probe = docs() else { return }
        let sql = "SELECT count(*) FROM framework_aliases WHERE synonyms IS NOT NULL AND synonyms<>''"
        let populated = probe.count(sql)
        #expect(populated >= 20, "expected ~22 framework synonyms attached, got \(populated)")
    }
}

/// Aliasing at the search door: a bare acronym should route to the canonical
/// framework page. Blocked by the same misbuild.
@Suite("Enrichment #11: Framework Aliasing via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment11FrameworkAliasingSearchTests {
    @Test("Bare acronym 'bluetooth' routes to CoreBluetooth")
    func bluetoothRoutesToCoreBluetooth() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let results = CupertinoCLI.searchDocs("bluetooth", ["--source", "apple-docs", "--limit", "10"])
        let hasCoreBluetooth = results.contains { $0.uri.lowercased().contains("corebluetooth") }
        #expect(hasCoreBluetooth, "bluetooth should route to CoreBluetooth via framework synonyms")
    }
}
