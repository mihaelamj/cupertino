@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #1282 — pin the exact canonical shipped database set

/// Before #1282 nothing pinned the EXACT canonical shipped set:
/// `ConstantsAuditTests.descriptorRegistryFloor` only asserts
/// `allKnown.count >= 10` (a floor over the descriptor+legacy union), and
/// `DatabaseBundleManifestTests` pins manifest-vs-registry drift (tautological
/// re: membership) and excludes only the legacy `search.db`. A floor cannot
/// catch an accidental ADDITION of a non-canonical DB to the shipped set, and
/// nothing asserted the orphan `samples.db` is excluded.
///
/// These tests pin `CLIImpl.bundleRequiredDescriptors()` (the single canonical
/// derivation `makeProductionSourceRegistry().allEnabled.map(\.destinationDB)`,
/// which is exactly what `cupertino setup` extracts and verifies) to the exact
/// canonical set by id, so BOTH an accidental addition and an accidental drop
/// fail as a discrete row, and assert the on-disk filename set a fresh install
/// receives carries neither the legacy unified `search.db` nor the orphan
/// `samples.db`. Adding a real source is then expected to update the literal
/// here in the same PR, which is the point: the canonical set is a reviewed
/// constant, not an emergent side effect.
@Suite("#1282 — canonical shipped database set is pinned exactly")
struct Issue1282CanonicalShippedSetTests {
    /// The canonical shipped sources, one per enabled production source
    /// (apple-docs, HIG, apple-archive, swift-evolution, swift-org, swift-book,
    /// sample-code, packages). DB ids, NOT source-prefix ids (the two are
    /// separate naming spaces; see `DatabaseDescriptor`).
    private static let canonicalIDs: Set<String> = [
        "apple-documentation",
        "hig",
        "apple-archive",
        "swift-evolution",
        "swift-org",
        "swift-book",
        "apple-sample-code",
        "packages",
    ]

    @Test("bundleRequiredDescriptors() is exactly the 8 canonical sources by id")
    func bundleRequiredIsExactlyCanonical() {
        let descriptors = CLIImpl.bundleRequiredDescriptors()
        let ids = Set(descriptors.map(\.id))

        // Exact equality catches BOTH an accidental addition (a new id appears)
        // AND an accidental drop (a canonical id disappears) — a floor cannot.
        #expect(ids == Self.canonicalIDs)
        #expect(descriptors.count == Self.canonicalIDs.count)
        // No duplicate descriptors slipped into the shipped set.
        #expect(descriptors.count == ids.count)
    }

    @Test("a fresh install's required filenames exclude the legacy search.db and orphan samples.db")
    func freshInstallExcludesLegacyAndOrphan() {
        let filenames = Set(CLIImpl.bundleRequiredDescriptors().map(\.filename))

        // The required-descriptor set is exactly what `cupertino setup`
        // extracts + post-extract-verifies (`SetupService.Request(required:)`),
        // so this pins the on-disk shape of a fresh install without a 742 MB
        // download. Neither the legacy unified search.db nor the pre-#1037
        // orphan samples.db may ship.
        #expect(!filenames.contains(Shared.Constants.FileName.searchDatabase))
        #expect(!filenames.contains(Shared.Constants.FileName.samplesDatabase))

        // The canonical sample-code DB ships under its post-#1037 filename.
        #expect(filenames.contains(Shared.Constants.FileName.appleSampleCodeDatabase))

        // And the legacy descriptor ids are not in the shipped set.
        let ids = Set(CLIImpl.bundleRequiredDescriptors().map(\.id))
        #expect(!ids.contains(Shared.Models.DatabaseDescriptor.search.id))
        #expect(!ids.contains(Shared.Models.DatabaseDescriptor.samples.id))
    }
}
