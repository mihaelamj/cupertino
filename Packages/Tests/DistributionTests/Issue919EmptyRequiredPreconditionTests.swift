import Distribution
import Foundation
import SharedConstants
import Testing

// MARK: - #919 coverage pins: classify(present:required:...) empty-required precondition

@Suite("#919 coverage: classify empty-required precondition")
struct Issue919EmptyRequiredPreconditionTests {
    @Test("classify(...) with a non-empty required set behaves identically pre/post-#919")
    func nonEmptyRequiredBehavesAsBefore() {
        // Pins the happy-path contract that the empty-required
        // precondition guards. With `required.isSubset(of: present)`,
        // any present-set that contains every required descriptor
        // resolves to .current / .stale / .unknown depending on the
        // installed-version stamp.
        let allThree: Set<Shared.Models.DatabaseDescriptor> = [.search, .samples, .packages]
        #expect(
            Distribution.InstalledVersion.classify(
                present: allThree,
                required: allThree,
                installedVersion: "1.2.0",
                currentVersion: "1.2.0"
            ) == .current(version: "1.2.0")
        )
        #expect(
            Distribution.InstalledVersion.classify(
                present: [.search, .samples],
                required: allThree,
                installedVersion: "1.2.0",
                currentVersion: "1.2.0"
            ) == .missing
        )
    }

    @Test("classify(...) ignores extra databases beyond the required set")
    func extraPresentDescriptorsAreIgnored() {
        // present.isSuperset(of: required) is the success path: extra
        // descriptors in `present` (a future 4th DB that this install
        // already carries) are not required to be in `required`. This
        // test pins the relaxed-subset semantic so a future caller
        // that hands in a superset doesn't accidentally classify as
        // .missing.
        let result = Distribution.InstalledVersion.classify(
            present: [.search, .samples, .packages],
            required: [.search],
            installedVersion: "1.2.0",
            currentVersion: "1.2.0"
        )
        #expect(result == .current(version: "1.2.0"))
    }
}
