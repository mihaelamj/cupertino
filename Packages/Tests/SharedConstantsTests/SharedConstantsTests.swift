import Foundation
@testable import SharedConstants
import Testing

// MARK: - SharedConstants Public API Smoke Tests

// SharedConstants is a zero-dependency leaf SPM target whose only role is to
// expose stable named values: paths, URLs, base directories, source-prefix
// metadata, and the cross-cutting `Sample` namespace shell. These tests
// guard the public surface against accidental renames or deletions during
// refactor passes; they do NOT verify the values themselves (those are
// implementation choices that can drift). They verify that every public
// path callers depend on still resolves at the qualified namespace path
// after a rebuild.
//
// Independence check (#382 acceptance): SharedConstants imports only
// `Foundation`. No other internal cupertino package is imported anywhere
// in this target. Verified by `grep -rln "^import " Packages/Sources/Shared/Constants/`.

@Suite("SharedConstants public surface")
struct SharedConstantsPublicSurfaceTests {
    @Test("Root Shared namespace anchor is reachable")
    func sharedNamespaceAnchor() {
        // The Shared namespace enum is declared here; types in every other
        // cupertino target extend it. If this lookup fails the entire
        // namespace tree under Shared.* breaks at compile time.
        _ = Shared.Constants.baseDirectoryName
    }

    @Test("Sample namespace shell exists")
    func sampleNamespaceAnchor() {
        // The cross-cutting Sample namespace lives in this target because
        // every consumer (Core, SampleIndex, Services, Search) imports
        // SharedConstants. Verify the anchor is in place.
        _ = Sample.self
    }

    @Test("Directory string constants are populated")
    func directoryConstants() {
        #expect(!Shared.Constants.Directory.docs.isEmpty)
        #expect(!Shared.Constants.Directory.swiftEvolution.isEmpty)
        #expect(!Shared.Constants.Directory.swiftOrg.isEmpty)
        #expect(!Shared.Constants.Directory.swiftBook.isEmpty)
        #expect(!Shared.Constants.Directory.packages.isEmpty)
        #expect(!Shared.Constants.Directory.sampleCode.isEmpty)
        #expect(!Shared.Constants.Directory.archive.isEmpty)
        #expect(!Shared.Constants.Directory.hig.isEmpty)
    }

    @Test("BaseURL constants are populated")
    func baseURLConstants() {
        #expect(Shared.Constants.BaseURL.appleDeveloper.hasPrefix("https://"))
        #expect(Shared.Constants.BaseURL.appleDeveloperDocs.hasPrefix("https://"))
        #expect(Shared.Constants.BaseURL.appleArchive.hasPrefix("https://"))
        #expect(Shared.Constants.BaseURL.appleArchiveDocs.hasPrefix("https://"))
        #expect(Shared.Constants.BaseURL.appleHIG.hasPrefix("https://"))
        #expect(Shared.Constants.BaseURL.appleSampleCode.hasPrefix("https://"))
        #expect(Shared.Constants.BaseURL.appleTutorialsData.hasPrefix("https://"))
        #expect(Shared.Constants.BaseURL.appleTutorialsDocs.hasPrefix("https://"))
    }
}
