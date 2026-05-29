import Foundation
import Testing

// Enrichment #12 — Platform Applicability.
//
// HIG topic-aware NULLing of platform floors that do not apply: a HIG
// topic that is macOS-only has its iOS/watchOS floors set to NULL (rather
// than inferred-positive). The signature in the DB is HIG rows with a
// mixed platform set — some floors populated, others deliberately NULL.
// Stored metadata with no dedicated search surface; DB-probe only.

@Suite("Enrichment #12 — Platform Applicability (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.hig)))
struct Enrichment12PlatformApplicabilityTests {
    private func hig() -> DBProbe? {
        DBProbe(LocalDBs.hig)
    }

    @Test("HIG has rows with floors populated (most topics apply broadly)")
    func higFloorsPopulated() {
        guard let probe = hig() else { return }
        #expect(probe.count("SELECT count(*) FROM docs_metadata WHERE min_ios IS NOT NULL") > 0)
    }

    @Test("Some HIG topics have a platform NULLed while others remain (applicability pruning ran)")
    func mixedApplicabilityExists() {
        guard let probe = hig() else { return }
        // A topic where iOS does not apply but macOS does (or the inverse)
        // proves the inference NULLed an inapplicable platform rather than
        // leaving every floor populated.
        let iosNullMacOSSet = probe.count(
            "SELECT count(*) FROM docs_metadata WHERE min_ios IS NULL AND min_macos IS NOT NULL"
        )
        let macOSNullIOSSet = probe.count(
            "SELECT count(*) FROM docs_metadata WHERE min_macos IS NULL AND min_ios IS NOT NULL"
        )
        #expect(
            iosNullMacOSSet + macOSNullIOSSet > 0,
            "no HIG topic shows a NULLed-but-not-all platform set; applicability pruning may not have run"
        )
    }
}
