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
    #expect(count == 606, "Should have 606 sample code entries")
    print("   ✅ Loaded \(count) sample code entries")
}

@Test("SampleCodeCatalog has correct metadata")
func sampleCodeCatalogMetadata() async throws {
    let version = await SampleCodeCatalog.version
    let lastCrawled = await SampleCodeCatalog.lastCrawled

    #expect(version == "1.0", "Version should be 1.0")
    #expect(lastCrawled == "2025-11-17", "Last crawled should be 2025-11-17")
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
    #expect(count == 9699, "Should have 9699 Swift packages")
    print("   ✅ Loaded \(count) Swift packages")
}

@Test("SwiftPackagesCatalog has correct metadata")
func swiftPackagesCatalogMetadata() async throws {
    let version = await SwiftPackagesCatalog.version
    let lastCrawled = await SwiftPackagesCatalog.lastCrawled
    let source = await SwiftPackagesCatalog.source

    #expect(version == "1.0", "Version should be 1.0")
    #expect(lastCrawled == "2025-11-17", "Last crawled should be 2025-11-17")
    #expect(source == "Swift Package Index + GitHub API", "Source should match")
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
    let stats = await PriorityPackagesCatalog.stats
    #expect(stats.totalPriorityPackages == 36, "Should have 36 priority packages total")
    #expect(stats.totalCriticalApplePackages == 31, "Should have 31 Apple packages")
    #expect(stats.totalEcosystemPackages == 5, "Should have 5 ecosystem packages")
    print("   ✅ Loaded \(stats.totalPriorityPackages) priority packages")
}

@Test("PriorityPackagesCatalog has correct metadata")
func priorityPackagesCatalogMetadata() async throws {
    let version = await PriorityPackagesCatalog.version
    let lastUpdated = await PriorityPackagesCatalog.lastUpdated
    let description = await PriorityPackagesCatalog.description

    #expect(version == "1.0", "Version should be 1.0")
    #expect(lastUpdated == "2025-11-17", "Last updated should be 2025-11-17")
    #expect(!description.isEmpty, "Description should not be empty")
    print("   ✅ Version: \(version), Last updated: \(lastUpdated)")
}

@Test("PriorityPackagesCatalog Apple packages are valid")
func priorityPackagesCatalogApplePackages() async throws {
    let applePackages = await PriorityPackagesCatalog.applePackages
    #expect(applePackages.count == 31, "Should have 31 Apple packages")

    // Verify known critical packages exist
    let repos = applePackages.map(\.repo)
    #expect(repos.contains("swift"), "Should contain swift")
    #expect(repos.contains("swift-nio"), "Should contain swift-nio")
    #expect(repos.contains("swift-testing"), "Should contain swift-testing")

    print("   ✅ Apple packages validated")
}

@Test("PriorityPackagesCatalog ecosystem packages are valid")
func priorityPackagesCatalogEcosystemPackages() async throws {
    let ecosystemPackages = await PriorityPackagesCatalog.ecosystemPackages
    #expect(ecosystemPackages.count == 5, "Should have 5 ecosystem packages")

    // Verify known ecosystem packages exist
    let fullNames = ecosystemPackages.map { "\($0.owner ?? "")/\($0.repo)" }
    #expect(fullNames.contains("vapor/vapor"), "Should contain vapor/vapor")
    #expect(fullNames.contains("pointfreeco/swift-composable-architecture"), "Should contain TCA")

    print("   ✅ Ecosystem packages validated")
}

@Test("PriorityPackagesCatalog priority check works")
func priorityPackagesCatalogPriorityCheck() async throws {
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
}

@Test("PriorityPackagesCatalog package lookup works")
func priorityPackagesCatalogPackageLookup() async throws {
    let swiftPackage = await PriorityPackagesCatalog.package(named: "swift")
    #expect(swiftPackage != nil, "Should find swift package")
    #expect(swiftPackage?.repo == "swift", "Package repo should match")

    let vaporPackage = await PriorityPackagesCatalog.package(named: "vapor")
    #expect(vaporPackage != nil, "Should find vapor package")
    #expect(vaporPackage?.owner == "vapor", "Vapor owner should be vapor")

    print("   ✅ Package lookup working correctly")
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
    let markdownFiles = findMarkdownFiles(in: tempDir)
    #expect(!markdownFiles.isEmpty, "Should have created at least one markdown file")

    if let firstFile = markdownFiles.first {
        try verifyMarkdownContent(firstFile)
    }
}

private func findMarkdownFiles(in directory: URL) -> [URL] {
    let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    )
    var markdownFiles: [URL] = []

    while let fileURL = enumerator?.nextObject() as? URL {
        if fileURL.pathExtension == "md" {
            markdownFiles.append(fileURL)
        }
    }

    return markdownFiles
}

private func verifyMarkdownContent(_ fileURL: URL) throws {
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content.count > 100, "Markdown content should be substantial")
    #expect(content.contains("Swift"), "Content should mention Swift")
    print("   ✅ Created markdown file: \(fileURL.lastPathComponent)")
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

// Note: Test tags are now defined in TestSupport/TestTags.swift
