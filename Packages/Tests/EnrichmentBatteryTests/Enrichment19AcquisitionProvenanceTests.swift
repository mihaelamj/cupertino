import Foundation
import Testing

// Enrichment #19 — Acquisition Provenance.
//
// How each doc was fetched/parsed, recorded in docs_metadata.source_type:
// appleJSON (DocC JSON API), appleWebKit (rendered HTML), custom (HIG /
// archive / evolution scrapers), swiftOrg (swift.org pages). Internal
// provenance, not a search filter, so DB-probe only.

@Suite("Enrichment #19 — Acquisition Provenance (real DBs)", .enabled(if: LocalDBs.anyDocsAvailable))
struct Enrichment19AcquisitionProvenanceTests {
    static let knownTypes: Set<String> = ["appleJSON", "appleWebKit", "custom", "swiftOrg"]

    @Test("Every docs DB uses only the known source_type vocabulary", arguments: LocalDBs.docsDBs)
    func vocabulary(db: String) {
        guard LocalDBs.available(db), let probe = DBProbe(db) else { return }
        let values = Set(probe.column("SELECT DISTINCT source_type FROM docs_metadata WHERE source_type IS NOT NULL AND source_type<>''"))
        #expect(!values.isEmpty, "\(db) has no source_type provenance")
        let unexpected = values.subtracting(Self.knownTypes)
        #expect(unexpected.isEmpty, "\(db) has unexpected source_type values: \(unexpected)")
    }

    @Test("apple-documentation is predominantly fetched via the DocC JSON API")
    func appleDocsUsesAppleJSON() {
        guard LocalDBs.available(LocalDBs.appleDocumentation), let probe = DBProbe(LocalDBs.appleDocumentation) else { return }
        #expect(
            probe.count("SELECT count(*) FROM docs_metadata WHERE source_type='appleJSON'") > 10000,
            "expected a large appleJSON share in apple-documentation"
        )
    }
}
