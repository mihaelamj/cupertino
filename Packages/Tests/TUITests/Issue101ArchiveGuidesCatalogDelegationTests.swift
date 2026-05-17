import Foundation
import SharedConstants
import Testing
@testable import TUI

// MARK: - #101: TUI delegation lock

/// Pre-#101 the TUI's `ArchiveGuidesCatalog.userSelectionsURL` and the
/// crawler's `Crawler.ArchiveGuideCatalog.userSelectionsFileURL(baseDirectory:)`
/// computed the same on-disk path independently. Either side could rename
/// the file (or join a different sub-directory) and silently split what
/// the TUI wrote from what the crawler read.
///
/// Post-#101 both sides delegate to `Shared.Paths.userArchiveSelectionsFile`.
/// `ArchiveGuidesCatalog.userSelectionsURL` is widened to `internal`
/// (from `private`) so this test can lock the delegation against the
/// canonical seam — the only consumer of the widened access is this
/// test target via `@testable import TUI`.
@Suite("#101 — TUI ArchiveGuidesCatalog delegates to Shared.Paths")
struct Issue101ArchiveGuidesCatalogDelegationTests {
    @Test("TUI.ArchiveGuidesCatalog.userSelectionsURL == Shared.Paths.live().userArchiveSelectionsFile")
    func tuiDelegatesToLiveSharedPaths() {
        // Both expressions resolve through `Shared.Paths.live()`, so they
        // observe the same baseDirectory at the same instant. The test
        // does no file I/O — comparing URL values is sufficient to lock
        // the delegation. The seam itself is exercised in
        // `SharedConstantsTests/Issue101UserArchiveSelectionsTests`.
        let tuiURL = ArchiveGuidesCatalog.userSelectionsURL
        let canonicalURL = Shared.Paths.live().userArchiveSelectionsFile

        #expect(tuiURL == canonicalURL, "TUI must delegate to Shared.Paths.userArchiveSelectionsFile")
    }

    @Test("TUI.ArchiveGuidesCatalog.userSelectionsURL filename is the canonical literal")
    func tuiUsesCanonicalFilename() {
        // Independent assertion that doesn't go through the seam — if the
        // delegation ever broke (e.g. a refactor reintroduced a local
        // literal), this would fail even if the seam is unchanged.
        #expect(ArchiveGuidesCatalog.userSelectionsURL.lastPathComponent
            == Shared.Constants.FileName.userArchiveSelections)
    }
}
