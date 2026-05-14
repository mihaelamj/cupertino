@testable import CorePackageIndexing
import CorePackageIndexingModels
import CoreProtocols
import Foundation
import SharedConstants
import Testing

// MARK: - Tests moved from CoreProtocolsTests during #536 phase 2a
//
// `Core.PackageIndexing.ExclusionList` and `Core.PackageIndexing.GitHubCanonicalizer`
// were moved out of CoreProtocols (foundation-only protocol seam) and into
// CorePackageIndexing (concrete impl with FileManager + URLSession I/O) so
// CoreProtocols stays pure of behavioural code per the foundation-only
// producer-target rule. Their smoke tests followed.

@Suite("Core.PackageIndexing — moved from CoreProtocols (#536 phase 2a)")
struct CorePackageIndexingMovedFromCoreProtocolsTests {
    // MARK: ExclusionList

    @Test("Core.PackageIndexing.ExclusionList.normalise strips whitespace and lowercases")
    func exclusionListNormalise() {
        // The exclusion-list format is a plain text file of one slug per
        // line; entries can carry stray whitespace or differ in case
        // across hand-curated files. Pin the normalisation contract so
        // a consumer comparing against it doesn't go off-rails.
        #expect(Core.PackageIndexing.ExclusionList.normalise("  SwiftUI  ") == "swiftui")
        #expect(Core.PackageIndexing.ExclusionList.normalise("UIKit") == "uikit")
        #expect(Core.PackageIndexing.ExclusionList.normalise("") == "")
    }

    // MARK: GitHubCanonicalizer

    @Test("Core.PackageIndexing.GitHubCanonicalizer.CanonicalName round-trips owner + repo")
    func gitHubCanonicalizerCanonicalName() {
        let name = Core.PackageIndexing.GitHubCanonicalizer.CanonicalName(owner: "apple", repo: "swift")
        #expect(name.owner == "apple")
        #expect(name.repo == "swift")
        // Equatable is part of the contract; conform-by-rename would
        // silently break dedup logic downstream.
        #expect(name == Core.PackageIndexing.GitHubCanonicalizer.CanonicalName(owner: "apple", repo: "swift"))
    }

    @Test("Core.PackageIndexing.GitHubCanonicalizer primes and snapshots its cache")
    func gitHubCanonicalizerCachePrimeAndSnapshot() async {
        // Don't write to disk for a smoke test; the actor accepts any
        // cache URL and only persists on demand.
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-leaf386-\(UUID().uuidString).json")
        let canonicalizer = Core.PackageIndexing.GitHubCanonicalizer(cacheURL: cacheURL)
        await canonicalizer.primeCache(
            inputOwner: "Mihaela",
            inputRepo: "Cupertino",
            canonicalOwner: "mihaelamj",
            canonicalRepo: "cupertino"
        )
        let snapshot = await canonicalizer.cacheSnapshot()
        // The snapshot key shape (input owner+repo lowercased) is an
        // implementation detail of the actor; instead of pinning the
        // exact key, just verify at least one entry now exists.
        #expect(!snapshot.isEmpty)
    }
}
