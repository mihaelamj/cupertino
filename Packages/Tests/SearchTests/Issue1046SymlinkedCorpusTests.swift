import Foundation
import SearchModels
import SearchStrategyHelpers
import Testing

// MARK: - #1046 regression: symlinked corpus directories

//
// `FileManager.default.enumerator(at:)` silently yields zero children
// when the input URL is a symlink to a directory (no error, no
// warning, just empty). Pre-#1046 `Search.StrategyHelpers.findDocFiles`
// and `findMarkdownFiles` passed the input URL as-is, so any user
// whose corpus dir was a symlink got silently empty indexes. Fix:
// resolve symlinks via `.resolvingSymlinksInPath()` before constructing
// the enumerator. This test pins the fix.
//

@Suite("Search.StrategyHelpers — symlinked corpus dirs (#1046)")
struct Issue1046SymlinkedCorpusTests {
    /// Build a fixture: <tmp>/real/<a.md, b.md, c.md, d.json> +
    /// <tmp>/link → <tmp>/real (symlink). Returns the link URL.
    private func makeSymlinkFixture() throws -> URL {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue-1046-\(UUID().uuidString)")
        let real = tmpRoot.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "# A".write(to: real.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "# B".write(to: real.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "# C".write(to: real.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: real.appendingPathComponent("d.json"), atomically: true, encoding: .utf8)
        let link = tmpRoot.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return link
    }

    @Test("findMarkdownFiles finds .md children when the input dir is a symlink")
    func findMarkdownFilesFollowsSymlink() throws {
        let link = try makeSymlinkFixture()
        defer { try? FileManager.default.removeItem(at: link.deletingLastPathComponent()) }
        let found = try Search.StrategyHelpers.findMarkdownFiles(in: link)
        #expect(found.count == 3, "should find a.md / b.md / c.md through the symlink; found \(found.count)")
    }

    @Test("findDocFiles finds .md + .json children when the input dir is a symlink")
    func findDocFilesFollowsSymlink() throws {
        let link = try makeSymlinkFixture()
        defer { try? FileManager.default.removeItem(at: link.deletingLastPathComponent()) }
        let found = try Search.StrategyHelpers.findDocFiles(in: link)
        // findDocFiles prefers JSON over .md siblings with the same basename;
        // here a/b/c have no .json siblings, d has no .md sibling. So expect 4.
        #expect(found.count == 4, "should find 3 .md + 1 .json through the symlink; found \(found.count)")
    }

    @Test("findMarkdownFiles still works on a non-symlinked dir (back-compat)")
    func findMarkdownFilesNoSymlink() throws {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue-1046-direct-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        try "# A".write(to: tmpRoot.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "# B".write(to: tmpRoot.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }
        let found = try Search.StrategyHelpers.findMarkdownFiles(in: tmpRoot)
        #expect(found.count == 2)
    }
}
