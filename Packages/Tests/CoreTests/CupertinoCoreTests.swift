import AppKit
@testable import Core
import Foundation
@testable import Search
@testable import Shared
import Testing
import TestSupport

@Test func hTMLToMarkdown() throws {
    let html = "<h1>Title</h1><p>Content</p>"
    let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)
    #expect(markdown.contains("# Title"))
}

// MARK: - SampleCodeCatalog Tests

@Test("SampleCodeCatalog loads from JSON resource")
func sampleCodeCatalogLoadsFromJSON() async throws {
    let count = await SampleCodeCatalog.count
    #expect(count > 500, "Should have hundreds of sample code entries")
    #expect(count < 1000, "Sample count should be reasonable")
    print("   ✅ Loaded \(count) sample code entries")
}

@Test("SampleCodeCatalog has correct metadata")
func sampleCodeCatalogMetadata() async throws {
    let version = await SampleCodeCatalog.version
    let lastCrawled = await SampleCodeCatalog.lastCrawled

    #expect(!version.isEmpty, "Version should not be empty")
    #expect(!lastCrawled.isEmpty, "Last crawled date should not be empty")
    print("   ✅ Version: \(version), Last crawled: \(lastCrawled)")
}

@Test("SampleCodeCatalog entries have required fields")
func sampleCodeCatalogEntriesValid() async throws {
    let entries = await SampleCodeCatalog.allEntries
    #expect(!entries.isEmpty, "Should have at least one entry")

    // Verify first entry has all required fields
    let firstEntry = entries[0]
    #expect(!firstEntry.title.isEmpty, "Entry should have title")
    #expect(!firstEntry.url.isEmpty, "Entry should have URL")
    #expect(!firstEntry.framework.isEmpty, "Entry should have framework")
    #expect(!firstEntry.description.isEmpty, "Entry should have description")
    #expect(!firstEntry.zipFilename.isEmpty, "Entry should have zipFilename")
    #expect(!firstEntry.webURL.isEmpty, "Entry should have webURL")

    print("   ✅ Sample entry: \(firstEntry.title)")
}

@Test("SampleCodeCatalog search works")
func sampleCodeCatalogSearch() async throws {
    let results = await SampleCodeCatalog.search("Swift")
    #expect(!results.isEmpty, "Search for 'Swift' should return results")

    // Verify search results contain the query
    for result in results.prefix(5) {
        let containsSwift = result.title.contains("Swift") || result.description.contains("Swift")
        #expect(containsSwift, "Search result should contain 'Swift'")
    }

    print("   ✅ Found \(results.count) results for 'Swift'")
}

@Test("SampleCodeCatalog framework filtering works")
func sampleCodeCatalogFrameworkFilter() async throws {
    let swiftUIEntries = await SampleCodeCatalog.entries(for: "SwiftUI")
    #expect(!swiftUIEntries.isEmpty, "Should have SwiftUI entries")

    // Verify all results are for the correct framework
    for entry in swiftUIEntries {
        #expect(entry.framework.lowercased() == "swiftui", "Entry should be SwiftUI framework")
    }

    print("   ✅ Found \(swiftUIEntries.count) SwiftUI entries")
}

// MARK: - SwiftPackagesCatalog Tests

@Test("SwiftPackagesCatalog loads from JSON resource")
func swiftPackagesCatalogLoadsFromJSON() async throws {
    let count = await SwiftPackagesCatalog.count
    #expect(count > 9000, "Should have thousands of Swift packages")
    #expect(count < 15000, "Package count should be reasonable")
    print("   ✅ Loaded \(count) Swift packages")
}

@Test("SwiftPackagesCatalog has correct metadata")
func swiftPackagesCatalogMetadata() async throws {
    let version = await SwiftPackagesCatalog.version
    let lastCrawled = await SwiftPackagesCatalog.lastCrawled
    let source = await SwiftPackagesCatalog.source

    #expect(!version.isEmpty, "Version should not be empty")
    #expect(!lastCrawled.isEmpty, "Last crawled date should not be empty")
    #expect(!source.isEmpty, "Source should not be empty")
    print("   ✅ Version: \(version), Last crawled: \(lastCrawled)")
    print("   ✅ Source: \(source)")
}

@Test("SwiftPackagesCatalog entries have required fields")
func swiftPackagesCatalogEntriesValid() async throws {
    let packages = await SwiftPackagesCatalog.allPackages
    #expect(!packages.isEmpty, "Should have at least one package")

    // Verify first entry has all required fields
    let firstPackage = packages[0]
    #expect(!firstPackage.owner.isEmpty, "Package should have owner")
    #expect(!firstPackage.repo.isEmpty, "Package should have repo")
    #expect(!firstPackage.url.isEmpty, "Package should have URL")
    // updatedAt is optional - some packages may not have it
    if let updatedAt = firstPackage.updatedAt {
        #expect(!updatedAt.isEmpty, "If updatedAt exists, it should not be empty")
    }

    print("   ✅ Sample package: \(firstPackage.owner)/\(firstPackage.repo)")
}

@Test("SwiftPackagesCatalog search works")
func swiftPackagesCatalogSearch() async throws {
    let results = await SwiftPackagesCatalog.search("SwiftUI")
    #expect(!results.isEmpty, "Search for 'SwiftUI' should return results")

    print("   ✅ Found \(results.count) results for 'SwiftUI'")
}

@Test("SwiftPackagesCatalog top packages returns sorted by stars")
func swiftPackagesCatalogTopPackages() async throws {
    let topPackages = await SwiftPackagesCatalog.topPackages(limit: 10)
    #expect(topPackages.count == 10, "Should return 10 top packages")

    // Verify they are sorted by stars (descending)
    for index in 0..<(topPackages.count - 1) {
        #expect(topPackages[index].stars >= topPackages[index + 1].stars, "Packages should be sorted by stars")
    }

    print("   ✅ Top package: \(topPackages[0].owner)/\(topPackages[0].repo) with \(topPackages[0].stars) stars")
}

@Test("SwiftPackagesCatalog active packages filter works")
func swiftPackagesCatalogActivePackages() async throws {
    let activePackages = await SwiftPackagesCatalog.activePackages(minStars: 100)
    #expect(!activePackages.isEmpty, "Should have active packages with 100+ stars")

    // Verify all are non-fork, non-archived, and have minimum stars
    for package in activePackages {
        #expect(!package.fork, "Package should not be a fork")
        #expect(!package.archived, "Package should not be archived")
        #expect(package.stars >= 100, "Package should have at least 100 stars")
    }

    print("   ✅ Found \(activePackages.count) active packages with 100+ stars")
}

// MARK: - PriorityPackagesCatalog Tests

@Test("PriorityPackagesCatalog loads from JSON resource")
func priorityPackagesCatalogLoadsFromJSON() async throws {
    // Use bundled file for consistent test results (not user's selected-packages.json)
    await PriorityPackagesCatalog.setUseBundledOnly(true)

    let stats = await PriorityPackagesCatalog.stats
    #expect(stats.totalPriorityPackages > 30, "Should have 30+ priority packages")
    #expect(stats.totalPriorityPackages < 50, "Priority package count should be reasonable")
    // These fields are optional to support TUI-generated files (which may not have them)
    if let appleCount = stats.totalCriticalApplePackages {
        #expect(appleCount > 25, "Should have 25+ Apple packages")
    }
    if let ecosystemCount = stats.totalEcosystemPackages {
        #expect(ecosystemCount > 0, "Should have ecosystem packages")
    }
    let applePackages = stats.totalCriticalApplePackages ?? 0
    let ecosystemPackages = stats.totalEcosystemPackages ?? 0
    let expectedTotal = applePackages + ecosystemPackages
    #expect(stats.totalPriorityPackages == expectedTotal, "Total should equal sum")
    print("   ✅ Loaded \(stats.totalPriorityPackages) priority packages")

    await PriorityPackagesCatalog.setUseBundledOnly(false)
}

@Test("PriorityPackagesCatalog has correct metadata")
func priorityPackagesCatalogMetadata() async throws {
    // Use bundled file for consistent test results
    await PriorityPackagesCatalog.setUseBundledOnly(true)

    let version = await PriorityPackagesCatalog.version
    let lastUpdated = await PriorityPackagesCatalog.lastUpdated
    let description = await PriorityPackagesCatalog.description

    #expect(!version.isEmpty, "Version should not be empty")
    #expect(!lastUpdated.isEmpty, "Last updated date should not be empty")
    #expect(!description.isEmpty, "Description should not be empty")
    print("   ✅ Version: \(version), Last updated: \(lastUpdated)")

    await PriorityPackagesCatalog.setUseBundledOnly(false)
}

@Test("PriorityPackagesCatalog Apple packages are valid")
func priorityPackagesCatalogApplePackages() async throws {
    // Use bundled file for consistent test results
    await PriorityPackagesCatalog.setUseBundledOnly(true)

    let applePackages = await PriorityPackagesCatalog.applePackages
    #expect(applePackages.count > 25, "Should have 25+ Apple packages")
    #expect(applePackages.count < 50, "Apple package count should be reasonable")

    // Verify known critical packages exist
    let repos = applePackages.map(\.repo)
    #expect(repos.contains("swift"), "Should contain swift")
    #expect(repos.contains("swift-nio"), "Should contain swift-nio")
    #expect(repos.contains("swift-testing"), "Should contain swift-testing")

    print("   ✅ Apple packages validated")

    await PriorityPackagesCatalog.setUseBundledOnly(false)
}

@Test("PriorityPackagesCatalog ecosystem packages are valid")
func priorityPackagesCatalogEcosystemPackages() async throws {
    // Use bundled file for consistent test results
    await PriorityPackagesCatalog.setUseBundledOnly(true)

    let ecosystemPackages = await PriorityPackagesCatalog.ecosystemPackages
    #expect(!ecosystemPackages.isEmpty, "Should have ecosystem packages")
    #expect(ecosystemPackages.count < 20, "Ecosystem package count should be reasonable")

    // Verify known ecosystem packages exist
    let fullNames = ecosystemPackages.map { "\($0.owner ?? "")/\($0.repo)" }
    #expect(fullNames.contains("vapor/vapor"), "Should contain vapor/vapor")
    #expect(fullNames.contains("pointfreeco/swift-composable-architecture"), "Should contain TCA")

    print("   ✅ Ecosystem packages validated")

    await PriorityPackagesCatalog.setUseBundledOnly(false)
}

@Test("PriorityPackagesCatalog priority check works")
func priorityPackagesCatalogPriorityCheck() async throws {
    // Use bundled file for consistent test results
    await PriorityPackagesCatalog.setUseBundledOnly(true)

    // Test known priority packages
    let isSwiftPriority = await PriorityPackagesCatalog.isPriority(owner: "apple", repo: "swift")
    let isNIOPriority = await PriorityPackagesCatalog.isPriority(owner: "apple", repo: "swift-nio")
    let isVaporPriority = await PriorityPackagesCatalog.isPriority(owner: "vapor", repo: "vapor")

    #expect(isSwiftPriority, "swift should be priority")
    #expect(isNIOPriority, "swift-nio should be priority")
    #expect(isVaporPriority, "vapor should be priority")

    // Test non-priority package
    let isRandomPriority = await PriorityPackagesCatalog.isPriority(owner: "random", repo: "package")
    #expect(!isRandomPriority, "random package should not be priority")

    print("   ✅ Priority check working correctly")

    await PriorityPackagesCatalog.setUseBundledOnly(false)
}

@Test("PriorityPackagesCatalog package lookup works")
func priorityPackagesCatalogPackageLookup() async throws {
    // Use bundled file for consistent test results
    await PriorityPackagesCatalog.setUseBundledOnly(true)

    do {
        let swiftPackage = await PriorityPackagesCatalog.package(named: "swift")
        #expect(swiftPackage != nil, "Should find swift package")
        #expect(swiftPackage?.repo == "swift", "Package repo should match")

        let vaporPackage = await PriorityPackagesCatalog.package(named: "vapor")
        #expect(vaporPackage != nil, "Should find vapor package")
        #expect(vaporPackage?.owner == "vapor", "Vapor owner should be vapor")

        print("   ✅ Package lookup working correctly")
    }

    // Reset after test - must await to avoid race condition
    await PriorityPackagesCatalog.setUseBundledOnly(false)
}

@Test("PriorityPackagesCatalog loads user file when available")
func priorityPackagesCatalogLoadsUserFile() async throws {
    // This test verifies issue #107 fix: user file takes precedence over bundled
    let userFileURL = Shared.Constants.defaultBaseDirectory
        .appendingPathComponent(Shared.Constants.FileName.selectedPackages)

    // Clear cache and ensure we're NOT using bundled-only mode
    await PriorityPackagesCatalog.setUseBundledOnly(false)

    // Check if user file exists
    guard FileManager.default.fileExists(atPath: userFileURL.path) else {
        // No user file - skip this test (falls back to bundled which is tested elsewhere)
        print("   ⚠️  Skipped: No user selections file at \(userFileURL.path)")
        return
    }

    // Read user file to get expected count
    let data = try Data(contentsOf: userFileURL)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tiers = json["tiers"] as? [String: Any] else {
        throw TestError("Failed to parse user selections file")
    }

    // Count packages in user file
    var userPackageCount = 0
    for (_, tierValue) in tiers {
        if let tier = tierValue as? [String: Any],
           let packages = tier["packages"] as? [[String: Any]] {
            userPackageCount += packages.count
        }
    }

    // Get packages from catalog (should read user file)
    let allPackages = await PriorityPackagesCatalog.allPackages

    // Verify catalog loaded user file (count should match)
    #expect(
        allPackages.count == userPackageCount,
        "Catalog should load \(userPackageCount) packages from user file, got \(allPackages.count)"
    )

    // Bundled file has 36 packages - if we got more, we're reading user file
    if userPackageCount > 36 {
        #expect(
            allPackages.count > 36,
            "User file has \(userPackageCount) packages, should not fall back to bundled 36"
        )
    }

    print("   ✅ User file loaded: \(allPackages.count) packages (user file has \(userPackageCount))")

    // Restore bundled-only for other tests
    await PriorityPackagesCatalog.setUseBundledOnly(true)
}

/// Custom test error
struct TestError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

// MARK: - Integration Tests

/// Integration test: Downloads a real Apple documentation page
/// This test makes actual network requests and requires internet connectivity
@Test(.tags(.integration))
@MainActor
func downloadRealAppleDocPage() async throws {
    // Set up NSApplication run loop for WKWebView
    _ = NSApplication.shared

    let tempDir = createTempDirectory()
    defer { cleanupTempDirectory(tempDir) }

    let config = createTestConfiguration(outputDirectory: tempDir)
    logTestStart(config: config)

    let crawler = await Core.Crawler(configuration: config)
    let stats = try await crawler.crawl()

    try verifyBasicStats(stats)
    try verifyOutputDirectory(tempDir)
    try verifyMarkdownFiles(tempDir)
    try verifyMetadata(config.changeDetection.metadataFile)

    print("🎉 Integration test passed!")
}

private func createTempDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-integration-test-\(UUID().uuidString)")
}

private func cleanupTempDirectory(_ tempDir: URL) {
    try? FileManager.default.removeItem(at: tempDir)
}

private func createTestConfiguration(outputDirectory: URL) -> Shared.Configuration {
    Shared.Configuration(
        crawler: Shared.CrawlerConfiguration(
            startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
            maxPages: 1,
            maxDepth: 1,
            outputDirectory: outputDirectory
        ),
        changeDetection: Shared.ChangeDetectionConfiguration(forceRecrawl: true),
        output: Shared.OutputConfiguration(format: .markdown)
    )
}

private func logTestStart(config: Shared.Configuration) {
    print("🧪 Integration Test: Downloading real Apple doc page...")
    print("   URL: \(config.crawler.startURL)")
    print("   Output: \(config.crawler.outputDirectory.path)")
}

private func verifyBasicStats(_ stats: CrawlStatistics) throws {
    #expect(stats.totalPages > 0, "Should have crawled at least 1 page")
    #expect(stats.newPages > 0, "Should have at least 1 new page")
    print("   ✅ Crawled \(stats.totalPages) page(s)")
}

private func verifyOutputDirectory(_ tempDir: URL) throws {
    var isDirectory: ObjCBool = false
    let dirExists = FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDirectory)
    #expect(dirExists && isDirectory.boolValue, "Output directory should exist")
}

private func verifyMarkdownFiles(_ tempDir: URL) throws {
    // Look for JSON or MD files (crawler now outputs JSON by default)
    let docFiles = findDocumentFiles(in: tempDir)
    #expect(!docFiles.isEmpty, "Should have created at least one documentation file")

    if let firstFile = docFiles.first {
        try verifyDocumentContent(firstFile)
    }
}

/// Find documentation files (JSON or markdown)
private func findDocumentFiles(in directory: URL) -> [URL] {
    let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    )
    var docFiles: [URL] = []

    while let fileURL = enumerator?.nextObject() as? URL {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "json" || ext == "md" {
            docFiles.append(fileURL)
        }
    }

    return docFiles
}

private func findMarkdownFiles(in directory: URL) -> [URL] {
    findDocumentFiles(in: directory).filter { $0.pathExtension == "md" }
}

private func verifyDocumentContent(_ fileURL: URL) throws {
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content.count > 100, "Documentation content should be substantial")
    #expect(content.lowercased().contains("swift"), "Content should mention Swift")
    print("   ✅ Created documentation file: \(fileURL.lastPathComponent)")
    print("   ✅ Content size: \(content.count) characters")
}

private func verifyMetadata(_ metadataFile: URL) throws {
    #expect(FileManager.default.fileExists(atPath: metadataFile.path), "Metadata file should be created")

    if FileManager.default.fileExists(atPath: metadataFile.path) {
        let metadata = try CrawlMetadata.load(from: metadataFile)
        #expect(!metadata.pages.isEmpty, "Metadata should contain page information")
        print("   ✅ Metadata created with \(metadata.pages.count) page(s)")
    }
}

// MARK: - CrawlerState Change Detection Tests

@Test("CrawlerState initializes with empty metadata")
func crawlerStateInitialization() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false
    )

    let state = CrawlerState(configuration: config)
    let pageCount = await state.getPageCount()

    #expect(pageCount == 0)
    print("   ✅ CrawlerState initialized with empty metadata")
}

@Test("CrawlerState loads existing metadata on initialization")
func crawlerStateLoadsExistingMetadata() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")

    // Create actual files that match the metadata
    let doc1Path = tempDir.appendingPathComponent("doc1.md")
    let doc2Path = tempDir.appendingPathComponent("doc2.md")
    try "# Doc 1".write(to: doc1Path, atomically: true, encoding: .utf8)
    try "# Doc 2".write(to: doc2Path, atomically: true, encoding: .utf8)

    // Create initial metadata with some pages (file paths must match real files)
    var metadata = CrawlMetadata()
    metadata.pages["https://example.com/doc1"] = PageMetadata(
        url: "https://example.com/doc1",
        framework: "test",
        filePath: doc1Path.path,
        contentHash: "hash1",
        depth: 0
    )
    metadata.pages["https://example.com/doc2"] = PageMetadata(
        url: "https://example.com/doc2",
        framework: "test",
        filePath: doc2Path.path,
        contentHash: "hash2",
        depth: 1
    )
    try metadata.save(to: metadataFile)

    // Initialize state - should load existing metadata
    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false
    )
    let state = CrawlerState(configuration: config)
    let pageCount = await state.getPageCount()

    #expect(pageCount == 2)
    print("   ✅ CrawlerState loaded existing metadata with \(pageCount) pages")
}

@Test("CrawlerState shouldRecrawl detects new pages")
func crawlerStateShouldRecrawlNewPage() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false
    )

    let state = CrawlerState(configuration: config)

    // New page should be recrawled
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/new-page",
        contentHash: "hash123",
        filePath: URL(fileURLWithPath: "/test/new.md")
    )

    #expect(shouldRecrawl)
    print("   ✅ New page correctly identified for crawling")
}

@Test("CrawlerState shouldRecrawl detects content changes")
func crawlerStateShouldRecrawlContentChanged() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("doc.md")

    // Create file and metadata
    try "Original content".write(to: outputFile, atomically: true, encoding: .utf8)

    var metadata = CrawlMetadata()
    metadata.pages["https://example.com/doc"] = PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "old-hash",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false
    )
    let state = CrawlerState(configuration: config)

    // Same URL but different hash should trigger recrawl
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "new-hash",
        filePath: outputFile
    )

    #expect(shouldRecrawl)
    print("   ✅ Content change correctly detected")
}

@Test("CrawlerState shouldRecrawl skips unchanged pages")
func crawlerStateShouldRecrawlSkipsUnchanged() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("doc.md")

    // Create file and metadata
    try "Content".write(to: outputFile, atomically: true, encoding: .utf8)

    var metadata = CrawlMetadata()
    metadata.pages["https://example.com/doc"] = PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "same-hash",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false
    )
    let state = CrawlerState(configuration: config)

    // Same URL, same hash, file exists - should skip
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "same-hash",
        filePath: outputFile
    )

    #expect(!shouldRecrawl)
    print("   ✅ Unchanged page correctly skipped")
}

@Test("CrawlerState shouldRecrawl detects missing files")
func crawlerStateShouldRecrawlMissingFile() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("missing.md")

    // Create metadata but NOT the file
    var metadata = CrawlMetadata()
    metadata.pages["https://example.com/doc"] = PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "hash123",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false
    )
    let state = CrawlerState(configuration: config)

    // File missing should trigger recrawl
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "hash123",
        filePath: outputFile
    )

    #expect(shouldRecrawl)
    print("   ✅ Missing file correctly detected")
}

@Test("CrawlerState respects forceRecrawl flag")
func crawlerStateForceRecrawl() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("doc.md")

    // Create file and metadata
    try "Content".write(to: outputFile, atomically: true, encoding: .utf8)

    var metadata = CrawlMetadata()
    metadata.pages["https://example.com/doc"] = PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "same-hash",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: true // Force recrawl
    )
    let state = CrawlerState(configuration: config)

    // Even with same hash and existing file, should recrawl when forced
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "same-hash",
        filePath: outputFile
    )

    #expect(shouldRecrawl)
    print("   ✅ forceRecrawl flag correctly enforced")
}

@Test("CrawlerState respects disabled change detection")
func crawlerStateDisabledChangeDetection() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("doc.md")

    // Create file and metadata
    try "Content".write(to: outputFile, atomically: true, encoding: .utf8)

    var metadata = CrawlMetadata()
    metadata.pages["https://example.com/doc"] = PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "same-hash",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.ChangeDetectionConfiguration(
        enabled: false, // Disabled
        metadataFile: metadataFile,
        forceRecrawl: false
    )
    let state = CrawlerState(configuration: config)

    // With change detection disabled, should always recrawl
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "same-hash",
        filePath: outputFile
    )

    #expect(shouldRecrawl)
    print("   ✅ Disabled change detection correctly handled")
}

@Test("CrawlerState updatePage adds page metadata")
func crawlerStateUpdatePage() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false
    )

    let state = CrawlerState(configuration: config)

    let initialCount = await state.getPageCount()
    #expect(initialCount == 0)

    // Update a page
    await state.updatePage(
        url: "https://example.com/doc",
        framework: "swift",
        filePath: "/test/doc.md",
        contentHash: "hash123",
        depth: 2
    )

    let newCount = await state.getPageCount()
    #expect(newCount == 1)
    print("   ✅ Page metadata successfully added")
}

@Test("CrawlerState updateStatistics modifies stats")
func crawlerStateUpdateStatistics() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false
    )

    let state = CrawlerState(configuration: config)

    await state.updateStatistics { stats in
        stats.totalPages = 10
        stats.newPages = 5
        stats.updatedPages = 3
        stats.skippedPages = 2
        stats.errors = 1
    }

    let stats = await state.getStatistics()
    #expect(stats.totalPages == 10)
    #expect(stats.newPages == 5)
    #expect(stats.updatedPages == 3)
    #expect(stats.skippedPages == 2)
    #expect(stats.errors == 1)
    print("   ✅ Statistics successfully updated")
}

@Test("CrawlerState session state management")
func crawlerStateSessionManagement() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false
    )

    let state = CrawlerState(configuration: config)

    // Initially no active session
    let hasActiveSession1 = await state.hasActiveSession()
    #expect(!hasActiveSession1)

    // Save session state
    let visited = Set(["https://example.com/1", "https://example.com/2"])
    let queue = [
        (url: URL(string: "https://example.com/3")!, depth: 1),
        (url: URL(string: "https://example.com/4")!, depth: 2),
    ]

    try await state.saveSessionState(
        visited: visited,
        queue: queue,
        startURL: URL(string: "https://example.com/start")!,
        outputDirectory: tempDir
    )

    // Now should have active session
    let hasActiveSession2 = await state.hasActiveSession()
    #expect(hasActiveSession2)

    // Get saved session
    let savedSession = await state.getSavedSession()
    #expect(savedSession != nil)
    #expect(savedSession?.visited.count == 2)
    #expect(savedSession?.queue.count == 2)

    // Clear session
    await state.clearSessionState()
    let hasActiveSession3 = await state.hasActiveSession()
    #expect(!hasActiveSession3)

    print("   ✅ Session state management working correctly")
}

@Test("CrawlerState finalizeCrawl saves metadata")
func crawlerStateFinalizeAndSave() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false
    )

    let state = CrawlerState(configuration: config)

    // Update some data
    await state.updatePage(
        url: "https://example.com/doc",
        framework: "swift",
        filePath: "/test/doc.md",
        contentHash: "hash123",
        depth: 0
    )

    let stats = CrawlStatistics(
        totalPages: 5,
        newPages: 3,
        updatedPages: 1,
        skippedPages: 1,
        errors: 0,
        startTime: Date(),
        endTime: Date()
    )

    // Finalize should save metadata
    try await state.finalizeCrawl(stats: stats)

    // Verify file exists
    #expect(FileManager.default.fileExists(atPath: metadataFile.path))

    // Verify we can load it back
    let loadedMetadata = try CrawlMetadata.load(from: metadataFile)
    #expect(loadedMetadata.pages.count == 1)
    #expect(loadedMetadata.stats.totalPages == 5)
    #expect(loadedMetadata.lastCrawl != nil)

    print("   ✅ Metadata finalized and saved correctly")
}

@Test("CrawlerState autoSaveIfNeeded respects interval")
func crawlerStateAutoSaveInterval() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let config = Shared.ChangeDetectionConfiguration(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false
    )

    let state = CrawlerState(configuration: config)

    let visited = Set(["https://example.com/1"])
    let queue = [(url: URL(string: "https://example.com/2")!, depth: 1)]
    let startURL = URL(string: "https://example.com/start")!

    // First auto-save should NOT happen immediately (interval not elapsed since init)
    try await state.autoSaveIfNeeded(
        visited: visited,
        queue: queue,
        startURL: startURL,
        outputDirectory: tempDir
    )

    // File should not exist yet - interval not elapsed
    #expect(!FileManager.default.fileExists(atPath: metadataFile.path))
    print("   ✅ Auto-save correctly skipped (interval not elapsed)")

    // Force a save using saveSessionState directly
    try await state.saveSessionState(
        visited: visited,
        queue: queue,
        startURL: startURL,
        outputDirectory: tempDir
    )

    // Now file should exist
    #expect(FileManager.default.fileExists(atPath: metadataFile.path))
    print("   ✅ Manual save succeeded")

    // Immediate auto-save call should not save again (interval not elapsed)
    let modDate1 = try FileManager.default.attributesOfItem(atPath: metadataFile.path)[.modificationDate] as? Date

    try await state.autoSaveIfNeeded(
        visited: visited,
        queue: queue,
        startURL: startURL,
        outputDirectory: tempDir
    )

    let modDate2 = try FileManager.default.attributesOfItem(atPath: metadataFile.path)[.modificationDate] as? Date

    // File should not have been modified (no new save)
    #expect(modDate1 == modDate2)
    print("   ✅ Auto-save respects interval (file not modified)")
}

@Test("HashUtilities sha256 produces consistent hashes")
func hashUtilitiesSHA256Consistency() throws {
    let content1 = "Hello, World!"
    let content2 = "Hello, World!"
    let content3 = "Different content"

    let hash1 = HashUtilities.sha256(of: content1)
    let hash2 = HashUtilities.sha256(of: content2)
    let hash3 = HashUtilities.sha256(of: content3)

    // Same content should produce same hash
    #expect(hash1 == hash2)

    // Different content should produce different hash
    #expect(hash1 != hash3)

    // Hash should be 64 characters (256 bits in hex)
    #expect(hash1.count == 64)

    print("   ✅ SHA-256 hashing working correctly")
}

// Note: Test tags are now defined in TestSupport/TestTags.swift
