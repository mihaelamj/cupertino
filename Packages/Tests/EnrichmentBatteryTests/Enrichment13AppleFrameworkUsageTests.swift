import Foundation
import Testing

// Enrichment #13 — Apple-Framework Usage.
//
// Which Apple frameworks each package imports, stored as a JSON array in
// package_metadata.apple_imports_json (distinct from #18 Dependency
// Closure, which is package-to-package SwiftPM deps). Stored metadata with
// no dedicated search filter; DB-probe only.

@Suite("Enrichment #13 — Apple-Framework Usage (real DBs)", .enabled(if: LocalDBs.packagesAvailable))
struct Enrichment13AppleFrameworkUsageTests {
    private func packages() -> DBProbe? {
        DBProbe(LocalDBs.packages)
    }

    @Test("apple_imports_json is populated on a meaningful share of packages")
    func populated() {
        guard let probe = packages() else { return }
        let found = probe.count(
            "SELECT count(*) FROM package_metadata WHERE apple_imports_json IS NOT NULL AND apple_imports_json NOT IN ('', '[]')"
        )
        #expect(found > 100, "expected >100 packages with Apple-framework usage, got \(found)")
    }

    @Test("Each apple_imports_json is a JSON array of lowercase framework names")
    func validJSONArrays() {
        guard let probe = packages() else { return }
        let samples = probe.column(
            "SELECT apple_imports_json FROM package_metadata WHERE apple_imports_json IS NOT NULL AND apple_imports_json NOT IN ('', '[]') LIMIT 50"
        )
        #expect(!samples.isEmpty)
        for json in samples {
            let data = Data(json.utf8)
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
                Issue.record("apple_imports_json not a JSON string array: \(json)")
                continue
            }
            #expect(!arr.isEmpty, "empty apple_imports array slipped past the NOT-IN filter: \(json)")
        }
    }

    @Test("A known Apple framework appears in at least one package's usage")
    func knownFrameworkAppears() {
        guard let probe = packages() else { return }
        let found = probe.count(
            "SELECT count(*) FROM package_metadata WHERE apple_imports_json LIKE '%foundation%'"
        )
        #expect(found > 0, "no package reports importing Foundation")
    }
}
