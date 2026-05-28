import Foundation
import Testing

// Enrichment #3 — Deployment Floors.
//
// Per-platform minimum-version columns (min_ios / min_macos / min_tvos /
// min_watchos / min_visionos) plus an availability_source provenance tag.
// They live on docs_metadata (docs DBs), projects (samples), and
// package_metadata (packages). Consumed at query time by the
// `--min-<platform>` search filters.
//
// DB-probe layer: columns present, populated on a meaningful fraction,
// floors well-formed, availability_source drawn from the known vocabulary.
// CLI layer: the --min-ios filter path runs and returns the available set.

@Suite("Enrichment #3 — Deployment Floors (real DBs)", .enabled(if: LocalDBs.anyAvailable))
struct Enrichment03DeploymentFloorsTests {
    static let floorColumns = ["min_ios", "min_macos", "min_tvos", "min_watchos", "min_visionos"]

    @Test("docs_metadata carries all five floor columns + availability_source", arguments: LocalDBs.docsDBs)
    func docsFloorColumns(db: String) {
        guard LocalDBs.available(db), let probe = DBProbe(db) else { return }
        let cols = Set(probe.tableColumns("docs_metadata"))
        for col in Self.floorColumns {
            #expect(cols.contains(col), "\(db) docs_metadata missing \(col)")
        }
        #expect(cols.contains("availability_source"), "\(db) missing availability_source")
    }

    @Test("apple-documentation has a meaningful fraction of populated iOS floors")
    func appleDocsFloorsPopulated() {
        guard LocalDBs.available(LocalDBs.appleDocumentation), let probe = DBProbe(LocalDBs.appleDocumentation) else { return }
        let found = probe.count("SELECT count(*) FROM docs_metadata WHERE min_ios IS NOT NULL")
        #expect(found > 50000, "expected >50k iOS floors in apple-documentation, got \(found)")
    }

    @Test("samples projects carry populated floors + valid availability_source")
    func samplesFloors() {
        guard LocalDBs.samplesAvailable, let probe = DBProbe(LocalDBs.appleSampleCode) else { return }
        let populated = probe.count("SELECT count(*) FROM projects WHERE min_ios IS NOT NULL")
        #expect(populated > 300, "expected >300 sample iOS floors, got \(populated)")
        // availability_source provenance: every non-empty value must be a known tag.
        let known: Set = ["sample-available-aggregated", "sample-framework-inferred", "sample-swift"]
        let bad = probe.column(
            "SELECT DISTINCT availability_source FROM projects WHERE availability_source IS NOT NULL AND availability_source <> ''"
        ).filter { !known.contains($0) }
        #expect(bad.isEmpty, "unexpected sample availability_source values: \(bad)")
    }

    @Test("packages carry populated floors + valid availability_source")
    func packagesFloors() {
        guard LocalDBs.packagesAvailable, let probe = DBProbe(LocalDBs.packages) else { return }
        let populated = probe.count("SELECT count(*) FROM package_metadata WHERE min_ios IS NOT NULL")
        #expect(populated > 50, "expected >50 package iOS floors, got \(populated)")
        let known: Set = ["package-available-aggregated", "package-swift"]
        let bad = probe.column(
            "SELECT DISTINCT availability_source FROM package_metadata WHERE availability_source IS NOT NULL AND availability_source <> ''"
        ).filter { !known.contains($0) }
        #expect(bad.isEmpty, "unexpected package availability_source values: \(bad)")
    }

    @Test("iOS floors are well-formed dotted versions (samples)")
    func floorsWellFormed() {
        guard LocalDBs.samplesAvailable, let probe = DBProbe(LocalDBs.appleSampleCode) else { return }
        // Every non-null min_ios must parse as a dotted numeric version.
        let malformed = probe.column(
            "SELECT DISTINCT min_ios FROM projects WHERE min_ios IS NOT NULL"
        ).filter { version in
            let parts = version.split(separator: ".")
            return parts.isEmpty || parts.contains { Int($0) == nil }
        }
        #expect(malformed.isEmpty, "malformed min_ios values: \(malformed)")
    }
}

/// The floors as the search pipeline consumes them: the --min-ios filter
/// runs end-to-end and returns the available sample set.
@Suite("Enrichment #3 — Deployment Floors via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment03DeploymentFloorsSearchTests {
    @Test("samples --min-ios 14.0 runs the floor filter and returns available samples")
    func samplesMinIOSFilterRuns() {
        guard LocalDBs.samplesAvailable else { return }
        let response = CupertinoCLI.searchSamples("swiftui", ["--min-ios", "14.0", "--limit", "50"])
        #expect(response != nil, "samples --min-ios query returned no parseable response")
        let projects = response?.projects.count ?? 0
        #expect(projects > 0, "expected available samples under --min-ios 14.0, got \(projects)")
    }
}
