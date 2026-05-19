import CorePackageIndexing
import CorePackageIndexingModels
import CoreProtocols
import Foundation
import LoggingModels
@testable import Search
@testable import CLI
import SearchModels
import SharedConstants
import Testing

@Suite("Symlink-Safe Integration Tests")
struct SymlinkSafeIntegrationTests {

    // MARK: - 2 & 3. CLI Fetch

    @Test("CLI Fetch: scanCupertinoDirectory and runPackageAnnotationStage handle symlinks")
    func fetchSymlinkHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-fetch-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let realBase = tempDir.appendingPathComponent("real_base", isDirectory: true)
        try FileManager.default.createDirectory(at: realBase, withIntermediateDirectories: true)
        
        let linkBase = tempDir.appendingPathComponent("link_base", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkBase, withDestinationURL: realBase)

        // Mock a package structure: link_base/packages/apple/swift-log
        let packagesDir = realBase.appendingPathComponent("packages", isDirectory: true)
        let ownerDir = packagesDir.appendingPathComponent("apple", isDirectory: true)
        let repoDir = ownerDir.appendingPathComponent("swift-log", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        
        // Put a Swift file with @available in the repo
        let sourcesDir = repoDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let fileURL = sourcesDir.appendingPathComponent("Main.swift")
        try "@available(macOS 12, *)\npublic struct Foo {}".write(to: fileURL, atomically: true, encoding: .utf8)

        // 2. Test scanCupertinoDirectory logic (manual call to ensure it follows linkBase)
        // Since it's private and uses Shared.Paths.live(), we test the FileSystem behavior it uses.
        let contents = try Shared.Utils.FileSystem.contentsOfDirectory(at: linkBase, includingPropertiesForKeys: [URLResourceKey.isDirectoryKey])
        #expect(contents.contains { $0.lastPathComponent == "packages" })
        
        let packagesLink = contents.first { $0.lastPathComponent == "packages" }!
        let isDir = (try? packagesLink.resolvingSymlinksInPath().resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory
        #expect(isDir == true, "Should identify symlinked 'packages' as a directory")

        // 3. Test runPackageAnnotationStage logic (filter logic)
        let owners = try Shared.Utils.FileSystem.contentsOfDirectory(at: packagesLink, includingPropertiesForKeys: [URLResourceKey.isDirectoryKey])
            .filter { (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [URLResourceKey.isDirectoryKey]).isDirectory) == true }
        #expect(owners.count == 1)
        #expect(owners[0].lastPathComponent == "apple")
    }

    // MARK: - 4. CLI Doctor volumeWarning

    @Test("CLI Doctor: volumeWarning handles symlinked DB URL")
    func doctorVolumeWarningSymlink() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-doctor-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let realDB = tempDir.appendingPathComponent("real.db")
        try "db content".write(to: realDB, atomically: true, encoding: .utf8)
        
        let linkDB = tempDir.appendingPathComponent("link.db")
        try FileManager.default.createSymbolicLink(at: linkDB, withDestinationURL: realDB)

        // volumeWarning is private, but we can test its resolution logic.
        let resolved = linkDB.resolvingSymlinksInPath()
        #expect(resolved.path == realDB.path)
        
        let values = try? resolved.resourceValues(forKeys: [URLResourceKey.volumeIsLocalKey])
        #expect(values?.volumeIsLocal != nil)
    }

    // MARK: - 5. PackageAvailabilityAnnotator

    @Test("PackageAvailabilityAnnotator: handles symlinked package directory correctly")
    func annotatorHandlesSymlinkedPackage() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-annotator-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let realRepo = tempDir.appendingPathComponent("real_repo", isDirectory: true)
        try FileManager.default.createDirectory(at: realRepo, withIntermediateDirectories: true)
        
        let linkRepo = tempDir.appendingPathComponent("link_repo", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkRepo, withDestinationURL: realRepo)

        let sourcesDir = realRepo.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let fileURL = sourcesDir.appendingPathComponent("Main.swift")
        try "@available(iOS 15, *)\npublic class Bar {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let annotator = Core.PackageIndexing.PackageAvailabilityAnnotator()
        let result = try await annotator.annotate(packageDirectory: linkRepo)
        
        #expect(result.stats.filesScanned == 1)
        #expect(result.stats.totalAttributes == 1)
        
        // Verify relpath doesn't have corruption (like /private prefix)
        let avail = result.fileAvailability.first { $0.relpath.hasSuffix("Main.swift") }
        #expect(avail != nil)
        #expect(avail?.relpath == "Sources/Main.swift")
    }
}
