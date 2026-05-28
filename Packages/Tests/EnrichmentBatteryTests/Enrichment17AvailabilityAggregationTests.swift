import Foundation
import Testing

// Enrichment #17 — Availability Aggregation.
//
// MAX-merge of per-file @available floors (captured by #8) with the
// declared Package.swift / framework floor. When the aggregated floor
// dominates, the row is tagged availability_source = "*-available-
// aggregated". The merged floor is consumed by the --min-ios search
// filter (#3), so this battery proves the aggregation tag + floor landed.

@Suite("Enrichment #17 — Availability Aggregation (real DBs)", .enabled(if: LocalDBs.samplesAvailable || LocalDBs.packagesAvailable))
struct Enrichment17AvailabilityAggregationTests {
    @Test("Some samples are tagged sample-available-aggregated with a floor")
    func samplesAggregated() {
        guard LocalDBs.samplesAvailable, let probe = DBProbe(LocalDBs.appleSampleCode) else { return }
        let tagged = probe.count("SELECT count(*) FROM projects WHERE availability_source='sample-available-aggregated'")
        #expect(tagged > 0, "no samples tagged as aggregated")
        let taggedWithFloor = probe.count(
            "SELECT count(*) FROM projects WHERE availability_source='sample-available-aggregated' AND min_ios IS NOT NULL"
        )
        #expect(taggedWithFloor > 0, "aggregated samples should carry a merged iOS floor")
    }

    @Test("Some packages are tagged package-available-aggregated with a floor")
    func packagesAggregated() {
        guard LocalDBs.packagesAvailable, let probe = DBProbe(LocalDBs.packages) else { return }
        let tagged = probe.count("SELECT count(*) FROM package_metadata WHERE availability_source='package-available-aggregated'")
        #expect(tagged > 0, "no packages tagged as aggregated")
        let taggedWithFloor = probe.count(
            "SELECT count(*) FROM package_metadata WHERE availability_source='package-available-aggregated' AND min_ios IS NOT NULL"
        )
        #expect(taggedWithFloor > 0, "aggregated packages should carry a merged iOS floor")
    }
}
