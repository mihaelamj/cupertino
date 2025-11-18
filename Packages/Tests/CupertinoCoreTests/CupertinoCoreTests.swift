import AppKit
@testable import CupertinoCore
@testable import CupertinoSearch
@testable import CupertinoShared
import Foundation
import Testing

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

    let crawler = await DocumentationCrawler(configuration: config)
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

private func createTestConfiguration(outputDirectory: URL) -> CupertinoConfiguration {
    CupertinoConfiguration(
        crawler: CrawlerConfiguration(
            startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
            maxPages: 1,
            maxDepth: 1,
            outputDirectory: outputDirectory
        ),
        changeDetection: ChangeDetectionConfiguration(forceRecrawl: true),
        output: OutputConfiguration(format: .markdown)
    )
}

private func logTestStart(config: CupertinoConfiguration) {
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

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
}
