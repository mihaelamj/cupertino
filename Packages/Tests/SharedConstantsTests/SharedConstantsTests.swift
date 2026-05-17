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

// MARK: - #101: user-archive-selections single source of truth

/// Both `Crawler.ArchiveGuideCatalog.userSelectionsFileURL(baseDirectory:)`
/// and `TUI/Models/ArchiveGuidesCatalog.userSelectionsURL` now resolve
/// the selection-file path through `Shared.Paths.userArchiveSelectionsFile`,
/// which itself reads the filename from
/// `Shared.Constants.FileName.userArchiveSelections`. The tests below
/// lock the filename literal + the `Shared.Paths` join shape so any
/// future change has to update exactly one declaration site — drift on
/// either end becomes mechanically impossible (or at minimum loud at
/// test time).
@Suite("#101 — user-archive-selections single source of truth")
struct Issue101UserArchiveSelectionsTests {
    @Test("FileName.userArchiveSelections is the canonical literal")
    func filenameConstantValue() {
        // Both Crawler and TUI consume this constant via Shared.Paths.
        // The literal value is contract-locked: changing it requires
        // also updating any persisted user files in the field.
        #expect(Shared.Constants.FileName.userArchiveSelections == "selected-archive-guides.json")
    }

    @Test("Shared.Paths.userArchiveSelectionsFile joins baseDirectory + canonical filename")
    func pathsJoin() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-test-\(UUID().uuidString)", isDirectory: true)
        let paths = Shared.Paths(baseDirectory: tmpDir)

        #expect(paths.userArchiveSelectionsFile == tmpDir
            .appendingPathComponent(Shared.Constants.FileName.userArchiveSelections))
        #expect(paths.userArchiveSelectionsFile.lastPathComponent == "selected-archive-guides.json")
    }

    @Test("Shared.Paths.userArchiveSelectionsFile sits directly under baseDirectory (no nesting)")
    func pathsNoExtraSegments() {
        // The file is a top-level state file alongside `metadata.json` and
        // `config.json` — not under a subdirectory. Locks the existing
        // on-disk layout so neither the crawler nor the TUI accidentally
        // nests it under e.g. `archive/` and silently splits the user's
        // selections from what the crawler reads.
        //
        // Compared by `.path` (not URL equality) because URL appends a
        // trailing slash after `deletingLastPathComponent()` on a file URL
        // that doesn't have one — this would falsely fail the structural
        // check the test is trying to make.
        let tmpDir = URL(fileURLWithPath: "/tmp/cupertino-test")
        let paths = Shared.Paths(baseDirectory: tmpDir)

        #expect(paths.userArchiveSelectionsFile.deletingLastPathComponent().path == tmpDir.path)
    }
}
