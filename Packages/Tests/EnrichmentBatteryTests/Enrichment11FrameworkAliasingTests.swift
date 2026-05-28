import Foundation
import Testing

// Enrichment #11 — Framework Aliasing.
//
// A framework_aliases table routes bare acronyms / informal names to their
// canonical framework root (bluetooth -> CoreBluetooth, nfc -> CoreNFC,
// ...). The 22 hand-curated aliases are attached by SynonymsPass via an
// UPDATE keyed on the `framework` column.
//
// KNOWN BLOCKER on this snapshot: apple-documentation.db was indexed with
// --docs-dir pointing one level too high, so `framework` = "docs" on
// ~351k/355k rows instead of the real framework identifier. The alias
// UPDATE therefore matches nothing and `synonyms` is empty on every docs
// DB. This is the caveat already recorded in docs/enrichment-inventory.md.
// The structural tests below pass; the behaviour tests are .disabled until
// the snapshot is rebuilt with --docs-dir .../docs (or the framework
// column is repaired from the URI).

@Suite("Enrichment #11 — Framework Aliasing (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
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

    @Test("Snapshot exhibits the documented framework='docs' misbuild")
    func misbuildIsPresentAndDocumented() {
        guard let probe = docs() else { return }
        // This pins the known-bad state so the battery makes the blocker
        // explicit. When the snapshot is rebuilt correctly this assertion
        // flips and is removed alongside re-enabling the behaviour tests.
        let docsFramework = probe.count("SELECT count(*) FROM docs_metadata WHERE framework='docs'")
        let total = probe.count("SELECT count(*) FROM docs_metadata")
        #expect(
            docsFramework > total / 2,
            "framework='docs' no longer dominates (\(docsFramework)/\(total)); the misbuild may be fixed — re-enable the behaviour tests"
        )
    }

    @Test(
        "The 22 framework synonyms are attached",
        .disabled("Blocked by apple-documentation.db framework='docs' misbuild; rebuild with --docs-dir .../docs")
    )
    func synonymsAttached() {
        guard let probe = docs() else { return }
        let populated = probe.count("SELECT count(*) FROM framework_aliases WHERE synonyms IS NOT NULL AND synonyms<>''")
        #expect(populated >= 20, "expected ~22 framework synonyms attached, got \(populated)")
    }
}

/// Aliasing at the search door: a bare acronym should route to the canonical
/// framework page. Blocked by the same misbuild.
@Suite("Enrichment #11 — Framework Aliasing via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment11FrameworkAliasingSearchTests {
    @Test(
        "Bare acronym 'bluetooth' routes to CoreBluetooth",
        .disabled("Blocked by apple-documentation.db framework='docs' misbuild; synonyms not attached on this snapshot")
    )
    func bluetoothRoutesToCoreBluetooth() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let results = CupertinoCLI.searchDocs("bluetooth", ["--source", "apple-docs", "--limit", "10"])
        let hasCoreBluetooth = results.contains { $0.uri.lowercased().contains("corebluetooth") }
        #expect(hasCoreBluetooth, "bluetooth should route to CoreBluetooth via framework synonyms")
    }
}
