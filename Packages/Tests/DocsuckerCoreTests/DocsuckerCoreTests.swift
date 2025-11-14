import Testing
import Foundation
@testable import DocsuckerCore
@testable import DocsuckerShared

@Test func testHTMLToMarkdown() throws {
    let html = "<h1>Title</h1><p>Content</p>"
    let markdown = HTMLToMarkdown.convert(html, url: URL(string: "https://example.com")!)
    #expect(markdown.contains("# Title"))
}

// MARK: - Integration Tests

/// Integration test: Downloads a real Apple documentation page
/// This test makes actual network requests and requires internet connectivity
@Test(.tags(.integration))
@MainActor
func testDownloadRealAppleDocPage() async throws {
    // Create temporary directory for test output
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("docsucker-integration-test-\(UUID().uuidString)")

    defer {
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // Configure crawler to download just 1 page
    let config = DocsuckerConfiguration(
        crawler: CrawlerConfiguration(
            startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
            maxPages: 1,
            maxDepth: 1,
            outputDirectory: tempDir
        ),
        changeDetection: ChangeDetectionConfiguration(
            forceRecrawl: true
        ),
        output: OutputConfiguration(format: .markdown)
    )

    print("🧪 Integration Test: Downloading real Apple doc page...")
    print("   URL: \(config.crawler.startURL)")
    print("   Output: \(tempDir.path)")

    // Create crawler and run
    let crawler = await DocumentationCrawler(configuration: config)
    let stats = try await crawler.crawl()

    // Verify results
    #expect(stats.totalPages > 0, "Should have crawled at least 1 page")
    #expect(stats.newPages > 0, "Should have at least 1 new page")

    print("   ✅ Crawled \(stats.totalPages) page(s)")

    // Verify output directory was created
    var isDirectory: ObjCBool = false
    let dirExists = FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDirectory)
    #expect(dirExists && isDirectory.boolValue, "Output directory should exist")

    // Check for markdown files (recursively, as they're organized by framework)
    let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: [.isRegularFileKey])
    var markdownFiles: [URL] = []

    while let fileURL = enumerator?.nextObject() as? URL {
        if fileURL.pathExtension == "md" {
            markdownFiles.append(fileURL)
        }
    }

    #expect(!markdownFiles.isEmpty, "Should have created at least one markdown file")

    if let firstFile = markdownFiles.first {
        let content = try String(contentsOf: firstFile, encoding: .utf8)

        // Verify markdown content has reasonable structure
        #expect(content.count > 100, "Markdown content should be substantial")
        #expect(content.contains("Swift"), "Content should mention Swift")

        print("   ✅ Created markdown file: \(firstFile.lastPathComponent)")
        print("   ✅ Content size: \(content.count) characters")
    }

    // Verify metadata was created
    let metadataFile = config.changeDetection.metadataFile
    #expect(FileManager.default.fileExists(atPath: metadataFile.path), "Metadata file should be created")

    if FileManager.default.fileExists(atPath: metadataFile.path) {
        let metadata = try CrawlMetadata.load(from: metadataFile)
        #expect(!metadata.pages.isEmpty, "Metadata should contain page information")
        print("   ✅ Metadata created with \(metadata.pages.count) page(s)")
    }

    print("🎉 Integration test passed!")
}

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
}
