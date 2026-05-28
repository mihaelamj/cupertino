import Foundation
import Testing

// Enrichment #18 — Dependency Closure.
//
// The transitive SwiftPM dependency graph per package, stored as a JSON
// array of "owner/repo" identifiers in package_metadata.parents_json,
// walked from each seed's Package.swift. Distinct from #13 (Apple
// frameworks the package imports). Stored metadata, DB-probe only.

@Suite("Enrichment #18 — Dependency Closure (real DBs)", .enabled(if: LocalDBs.packagesAvailable))
struct Enrichment18DependencyClosureTests {
    private func packages() -> DBProbe? {
        DBProbe(LocalDBs.packages)
    }

    @Test("parents_json is populated across packages")
    func populated() {
        guard let probe = packages() else { return }
        #expect(probe.count("SELECT count(*) FROM package_metadata WHERE parents_json IS NOT NULL AND parents_json<>''") > 100)
    }

    @Test("Non-empty closures are JSON arrays of owner/repo identifiers")
    func validClosureShape() {
        guard let probe = packages() else { return }
        let samples = probe.column(
            "SELECT parents_json FROM package_metadata WHERE parents_json IS NOT NULL AND parents_json NOT IN ('', '[]', '{}') LIMIT 30"
        )
        #expect(!samples.isEmpty, "no non-empty dependency closures found")
        for json in samples {
            let data = Data(json.utf8)
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
                Issue.record("parents_json not a JSON string array: \(json)")
                continue
            }
            // Each identifier should be an owner/repo slug.
            #expect(arr.allSatisfy { $0.contains("/") }, "dependency identifiers should be owner/repo slugs: \(arr)")
        }
    }
}
