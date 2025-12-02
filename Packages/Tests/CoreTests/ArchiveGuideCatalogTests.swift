@testable import Core
import Foundation
@testable import Shared
import Testing

// MARK: - ArchiveGuideCatalog Tests

@Test("ArchiveGuideCatalog loads bundled catalog")
func archiveGuideCatalogLoadsBundledCatalog() throws {
    let requiredPaths = ArchiveGuideCatalog.getRequiredGuidePaths()
    #expect(!requiredPaths.isEmpty, "Should have required guide paths from bundled catalog")
    print("   ✅ Found \(requiredPaths.count) required guides in bundled catalog")
}

@Test("ArchiveGuideCatalog required guides include Core frameworks")
func archiveGuideCatalogRequiredGuidesIncludeCoreFrameworks() throws {
    let requiredPaths = ArchiveGuideCatalog.getRequiredGuidePaths()

    // Check for expected Core framework guides
    let hasQuartz2D = requiredPaths.contains { $0.contains("drawingwithquartz2d") }
    let hasCoreAnimation = requiredPaths.contains { $0.contains("CoreAnimation") }

    #expect(hasQuartz2D, "Required guides should include Quartz 2D (CoreGraphics)")
    #expect(hasCoreAnimation, "Required guides should include Core Animation (QuartzCore)")
    print("   ✅ Required guides include Core framework documentation")
}

@Test("ArchiveGuideCatalog creates user file if missing")
func archiveGuideCatalogCreatesUserFileIfMissing() throws {
    let fileURL = ArchiveGuideCatalog.userSelectionsFileURL

    // Backup existing file if present
    let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("selected-archive-guides.backup.json")
    var hadExistingFile = false
    if FileManager.default.fileExists(atPath: fileURL.path) {
        hadExistingFile = true
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
    }

    defer {
        // Restore backup if we had one
        if hadExistingFile {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.moveItem(at: backupURL, to: fileURL)
        }
    }

    // Ensure file doesn't exist
    #expect(!ArchiveGuideCatalog.userSelectionsFileExists, "File should not exist before test")

    // Access essentialGuides - this should create the file
    let guides = ArchiveGuideCatalog.essentialGuides
    #expect(!guides.isEmpty, "Should return guides")

    // File should now exist
    #expect(ArchiveGuideCatalog.userSelectionsFileExists, "File should be created after accessing essentialGuides")
    print("   ✅ User selections file created automatically")
}

@Test("ArchiveGuideCatalog does not overwrite existing user file")
func archiveGuideCatalogDoesNotOverwriteExistingFile() throws {
    let fileURL = ArchiveGuideCatalog.userSelectionsFileURL

    // Backup existing file if present
    let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("selected-archive-guides.backup.json")
    var hadExistingFile = false
    if FileManager.default.fileExists(atPath: fileURL.path) {
        hadExistingFile = true
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
    }

    defer {
        // Restore backup if we had one
        try? FileManager.default.removeItem(at: fileURL)
        if hadExistingFile {
            try? FileManager.default.moveItem(at: backupURL, to: fileURL)
        }
    }

    // Create a custom user file with specific content
    let customContent = """
    {
      "count": 1,
      "description": "Test file - should not be overwritten",
      "guides": [
        {
          "category": "Test",
          "framework": "TestFramework",
          "path": "Test/Custom/Path",
          "title": "Custom Test Guide"
        }
      ],
      "lastUpdated": "2024-01-01T00:00:00Z",
      "version": "1.0"
    }
    """

    // Ensure directory exists
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try customContent.write(to: fileURL, atomically: true, encoding: .utf8)

    // Get modification date
    let attrs1 = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let modDate1 = attrs1[.modificationDate] as? Date

    // Access essentialGuides - should NOT overwrite
    let guides = ArchiveGuideCatalog.essentialGuides
    #expect(!guides.isEmpty, "Should return guides")

    // Check file wasn't modified
    let attrs2 = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let modDate2 = attrs2[.modificationDate] as? Date

    #expect(modDate1 == modDate2, "File should not be modified if it already exists")

    // Verify custom content is still there
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content.contains("Custom Test Guide"), "Custom content should be preserved")
    print("   ✅ Existing user file not overwritten")
}

@Test("ArchiveGuideCatalog essentialGuides returns valid URLs")
func archiveGuideCatalogEssentialGuidesReturnsValidURLs() throws {
    let guides = ArchiveGuideCatalog.essentialGuides
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

@Test("ArchiveGuideCatalog testGuides returns minimal set")
func archiveGuideCatalogTestGuidesReturnsMinimalSet() throws {
    let testGuides = ArchiveGuideCatalog.testGuides
    #expect(!testGuides.isEmpty, "Should have at least one test guide")
    #expect(testGuides.count <= 3, "Test guides should be a minimal set for testing")

    // Should contain ObjC Runtime Guide
    let hasObjCRuntime = testGuides.contains { $0.absoluteString.contains("ObjCRuntimeGuide") }
    #expect(hasObjCRuntime, "Test guides should include ObjC Runtime Guide")
    print("   ✅ Test guides: \(testGuides.count) guide(s)")
}

@Test("ArchiveGuideCatalog userSelectionsFileURL points to correct location")
func archiveGuideCatalogUserSelectionsFileURLCorrect() throws {
    let fileURL = ArchiveGuideCatalog.userSelectionsFileURL
    let expectedPath = Shared.Constants.defaultBaseDirectory.appendingPathComponent("selected-archive-guides.json")

    #expect(fileURL == expectedPath, "User selections file should be in ~/.cupertino/")
    #expect(fileURL.lastPathComponent == "selected-archive-guides.json", "File should be named selected-archive-guides.json")
    print("   ✅ User selections file URL: \(fileURL.path)")
}

@Test("ArchiveGuideCatalog created file contains only required guides")
func archiveGuideCatalogCreatedFileContainsOnlyRequiredGuides() throws {
    let fileURL = ArchiveGuideCatalog.userSelectionsFileURL

    // Backup existing file if present
    let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("selected-archive-guides.backup.json")
    var hadExistingFile = false
    if FileManager.default.fileExists(atPath: fileURL.path) {
        hadExistingFile = true
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
    }

    defer {
        // Restore backup if we had one
        try? FileManager.default.removeItem(at: fileURL)
        if hadExistingFile {
            try? FileManager.default.moveItem(at: backupURL, to: fileURL)
        }
    }

    // Ensure file doesn't exist
    if FileManager.default.fileExists(atPath: fileURL.path) {
        try FileManager.default.removeItem(at: fileURL)
    }

    // Trigger file creation
    _ = ArchiveGuideCatalog.essentialGuides

    // Read created file
    let data = try Data(contentsOf: fileURL)
    let json = try JSONDecoder().decode(TestSelectedGuidesJSON.self, from: data)

    // Get required guides from bundled catalog
    let requiredPaths = Set(ArchiveGuideCatalog.getRequiredGuidePaths())

    // All guides in created file should be required
    for guide in json.guides {
        #expect(
            requiredPaths.contains(guide.path),
            "Created file should only contain required guides, but found: \(guide.path)"
        )
    }

    #expect(
        json.guides.count == requiredPaths.count,
        "Created file should have same count as required guides"
    )
    print("   ✅ Created file contains exactly \(json.guides.count) required guides")
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
