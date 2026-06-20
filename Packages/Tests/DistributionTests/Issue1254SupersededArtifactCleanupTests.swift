@testable import Distribution
import Foundation
import Testing

/// #1254: after a verified per-source extraction, `cupertino setup` must
/// remove the pre-#1036 artifacts the per-source bundle supersedes (the
/// unified `search.db`, the old `samples.db`, the `search/` extraction
/// dir, and their SQLite sidecars), which otherwise sit as multi-GB dead
/// weight alongside the new per-source DBs. The detection is a pure
/// function pinned here; the removal is exercised end-to-end against a
/// temp directory.
@Suite("Distribution.SetupService superseded-artifact cleanup (#1254)")
struct Issue1254SupersededArtifactCleanupTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-1254-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ url: URL, bytes: Int = 16) throws {
        try Data(repeating: 0, count: bytes).write(to: url)
    }

    @Test("detects search.db / samples.db / search-dir and their sidecars, not the live per-source DBs")
    func detectsSupersededArtifacts() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Superseded pre-#1036 artifacts.
        try touch(dir.appendingPathComponent("search.db"))
        try touch(dir.appendingPathComponent("search.db-wal"))
        try touch(dir.appendingPathComponent("search.db-shm"))
        try touch(dir.appendingPathComponent("samples.db"))
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("search"),
            withIntermediateDirectories: true
        )
        // Live per-source DBs that must NOT be flagged.
        try touch(dir.appendingPathComponent("apple-documentation.db"))
        try touch(dir.appendingPathComponent("apple-sample-code.db"))

        let placements: Set = ["apple-documentation.db", "apple-sample-code.db", "packages.db"]
        let found = Set(
            Distribution.SetupService
                .supersededLegacyArtifacts(in: dir, currentPlacementFilenames: placements)
                .map(\.lastPathComponent)
        )

        #expect(found == ["search.db", "search.db-wal", "search.db-shm", "samples.db", "search"])
        #expect(!found.contains("apple-documentation.db"))
        #expect(!found.contains("apple-sample-code.db"))
    }

    @Test("never flags an artifact name that is also a current placement")
    func neverFlagsCurrentPlacement() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try touch(dir.appendingPathComponent("samples.db"))

        // Defensive guard: if some future bundle shipped `samples.db` as a
        // live placement, it must not be removed.
        let found = Distribution.SetupService.supersededLegacyArtifacts(
            in: dir,
            currentPlacementFilenames: ["samples.db"]
        )
        #expect(found.isEmpty)
    }

    @Test("returns nothing on a clean per-source-only install")
    func cleanInstallHasNothingToRemove() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try touch(dir.appendingPathComponent("apple-documentation.db"))
        try touch(dir.appendingPathComponent("hig.db"))

        let found = Distribution.SetupService.supersededLegacyArtifacts(
            in: dir,
            currentPlacementFilenames: ["apple-documentation.db", "hig.db"]
        )
        #expect(found.isEmpty)
    }
}
