import CorePackageIndexingModels
import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

@Suite("PackageIndexer Symlink Safety")
struct PackageIndexerSymlinkTests {
    @Test("indexer follows symlinked Sources directory")
    func indexerFollowsSymlinkedSources() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-indexer-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // root/owner/repo/
        let pkgDir = tempDir.appendingPathComponent("owner/repo", isDirectory: true)
        try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)

        let realSources = tempDir.appendingPathComponent("real_sources", isDirectory: true)
        try FileManager.default.createDirectory(at: realSources, withIntermediateDirectories: true)
        let fileURL = realSources.appendingPathComponent("Main.swift")
        try "public struct Foo {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let linkSources = pkgDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkSources, withDestinationURL: realSources)

        let manifest = """
        {
            "owner": "owner",
            "repo": "repo",
            "url": "https://github.com/owner/repo"
        }
        """
        try manifest.write(to: pkgDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let dbPath = tempDir.appendingPathComponent("packages.db")
        let index = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
        let indexer = Search.PackageIndexer(rootDirectory: tempDir, index: index)

        let stats = try await indexer.indexAll()
        
        // Assertions
        #expect(stats.packagesIndexed == 1, "Should have indexed 1 package")
        #expect(stats.totalFiles >= 1, "Should have indexed at least 1 file (Main.swift)")

        let summary = try await index.summary()
        #expect(summary.fileCount >= 1, "Database should contain at least 1 file")
    }

    @Test("indexer handles symlinked repo directory")
    func indexerHandlesSymlinkedRepo() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-repo-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ownerDir = tempDir.appendingPathComponent("owner", isDirectory: true)
        try FileManager.default.createDirectory(at: ownerDir, withIntermediateDirectories: true)

        let realRepo = tempDir.appendingPathComponent("real_repo", isDirectory: true)
        try FileManager.default.createDirectory(at: realRepo, withIntermediateDirectories: true)
        
        // Put file in Sources so it's classified as .source
        let sourcesDir = realRepo.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let fileURL = sourcesDir.appendingPathComponent("Main.swift")
        try "public struct Bar {}".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let manifest = """
        {
            "owner": "owner",
            "repo": "repo",
            "url": "https://github.com/owner/repo"
        }
        """
        try manifest.write(to: realRepo.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let linkRepo = ownerDir.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkRepo, withDestinationURL: realRepo)

        let dbPath = tempDir.appendingPathComponent("packages-repo.db")
        let index = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
        let indexer = Search.PackageIndexer(rootDirectory: tempDir, index: index)

        let stats = try await indexer.indexAll()
        
        #expect(stats.packagesIndexed == 1, "Should have indexed 1 package via symlinked repo dir")
        #expect(stats.totalFiles >= 1, "Should have found the file inside the symlinked repo")
    }
}
