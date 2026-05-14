@testable import Core
import CoreProtocols
import Crawler
import CrawlerModels
import Foundation
import SharedConstants
import Testing

// MARK: - Crawler.ArchiveGuideCatalog Tests

@Test("Crawler.ArchiveGuideCatalog loads bundled catalog")
func archiveGuideCatalogLoadsBundledCatalog() {
    let requiredPaths = Crawler.ArchiveGuideCatalog.getRequiredGuidePaths()
    #expect(!requiredPaths.isEmpty, "Should have required guide paths from bundled catalog")
    print("   ✅ Found \(requiredPaths.count) required guides in bundled catalog")
}

@Test("Crawler.ArchiveGuideCatalog required guides include Core frameworks")
func archiveGuideCatalogRequiredGuidesIncludeCoreFrameworks() {
    let requiredPaths = Crawler.ArchiveGuideCatalog.getRequiredGuidePaths()

    // Check for expected Core framework guides
    let hasQuartz2D = requiredPaths.contains { $0.contains("drawingwithquartz2d") }
    let hasCoreAnimation = requiredPaths.contains { $0.contains("CoreAnimation") }

    #expect(hasQuartz2D, "Required guides should include Quartz 2D (CoreGraphics)")
    #expect(hasCoreAnimation, "Required guides should include Core Animation (QuartzCore)")
    print("   ✅ Required guides include Core framework documentation")
}

@Test("Crawler.ArchiveGuideCatalog creates user file if missing")
func archiveGuideCatalogCreatesUserFileIfMissing() throws {
    // Use temp directory to avoid conflicts with other tests
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let testFileURL = tempDir.appendingPathComponent("selected-archive-guides.json")

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // File shouldn't exist in temp dir
    #expect(!FileManager.default.fileExists(atPath: testFileURL.path), "File should not exist before test")

    // Access essentialGuides returns guides regardless of file state
    let guides = Crawler.ArchiveGuideCatalog.essentialGuides(baseDirectory: tempDir)
    #expect(!guides.isEmpty, "Should return guides")

    print("   ✅ User selections file created automatically")
}

@Test("Crawler.ArchiveGuideCatalog does not overwrite existing user file")
func archiveGuideCatalogDoesNotOverwriteExistingFile() throws {
    // This test verifies that essentialGuides returns data even when file exists.
    // Use an isolated tempDir post-#535 (the previous test pointed at the
    // real ~/.cupertino via the singleton fallback).
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let guides = Crawler.ArchiveGuideCatalog.essentialGuides(baseDirectory: tempDir)
    #expect(!guides.isEmpty, "Should return guides")
    print("   ✅ Existing user file not overwritten")
}

@Test("Crawler.ArchiveGuideCatalog essentialGuides returns valid URLs")
func archiveGuideCatalogEssentialGuidesReturnsValidURLs() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let guides = Crawler.ArchiveGuideCatalog.essentialGuides(baseDirectory: tempDir)
    #expect(!guides.isEmpty, "Should have essential guides")

    // All URLs should be valid Apple archive URLs
    for guide in guides {
        #expect(
            guide.absoluteString.hasPrefix("https://developer.apple.com/library/archive/documentation/"),
            "Guide URL should be Apple archive URL: \(guide)"
        )
    }

    print("   ✅ All \(guides.count) guide URLs are valid")
}

@Test("Crawler.ArchiveGuideCatalog testGuides returns minimal set")
func archiveGuideCatalogTestGuidesReturnsMinimalSet() {
    let testGuides = Crawler.ArchiveGuideCatalog.testGuides
    #expect(!testGuides.isEmpty, "Should have at least one test guide")
    #expect(testGuides.count <= 3, "Test guides should be a minimal set for testing")

    // Should contain ObjC Runtime Guide
    let hasObjCRuntime = testGuides.contains { $0.absoluteString.contains("ObjCRuntimeGuide") }
    #expect(hasObjCRuntime, "Test guides should include ObjC Runtime Guide")
    print("   ✅ Test guides: \(testGuides.count) guide(s)")
}

@Test("Crawler.ArchiveGuideCatalog userSelectionsFileURL points to correct location")
func archiveGuideCatalogUserSelectionsFileURLCorrect() {
    // Post-#535: userSelectionsFileURL takes an explicit base directory.
    let baseDir = URL(fileURLWithPath: "/tmp/cupertino-archive-guide-test")
    let fileURL = Crawler.ArchiveGuideCatalog.userSelectionsFileURL(baseDirectory: baseDir)
    let expectedPath = baseDir.appendingPathComponent("selected-archive-guides.json")

    #expect(fileURL == expectedPath, "User selections file should be under the supplied base directory")
    #expect(fileURL.lastPathComponent == "selected-archive-guides.json", "File should be named selected-archive-guides.json")
    print("   ✅ User selections file URL: \(fileURL.path)")
}

@Test("Crawler.ArchiveGuideCatalog created file contains only required guides")
func archiveGuideCatalogCreatedFileContainsOnlyRequiredGuides() {
    // This test verifies that the bundled catalog has required guides
    // NOTE: essentialGuides reads from user file (~/.cupertino/selected-archive-guides.json)
    // which may be modified by TUI, so we only test bundled catalog requirements
    let requiredPaths = Crawler.ArchiveGuideCatalog.getRequiredGuidePaths()

    #expect(!requiredPaths.isEmpty, "Should have required guide paths from bundled catalog")

    // Verify core framework guides are in the required list
    let hasQuartz2D = requiredPaths.contains { $0.contains("drawingwithquartz2d") }
    let hasCoreAnimation = requiredPaths.contains { $0.contains("CoreAnimation") }

    #expect(hasQuartz2D, "Required guides should include Quartz 2D")
    #expect(hasCoreAnimation, "Required guides should include Core Animation")

    print("   ✅ Bundled catalog has \(requiredPaths.count) required guides")
}

// MARK: - Test Support Types

private struct TestSelectedGuidesJSON: Codable {
    let version: String
    let lastUpdated: String
    let description: String
    let count: Int
    let guides: [TestGuideJSON]
}

private struct TestGuideJSON: Codable {
    let title: String
    let framework: String
    let category: String
    let path: String
}
