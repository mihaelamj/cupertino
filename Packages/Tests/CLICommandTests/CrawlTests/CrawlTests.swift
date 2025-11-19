import AppKit
@testable import CLI
@testable import Core
import Foundation
@testable import Search
@testable import Shared
import Testing
import TestSupport

// MARK: - Crawl Command Tests

/// Tests for the `cupertino crawl` command
/// Verifies crawling functionality, resume capability, and Evolution proposals

@Suite("Crawl Command Tests")
struct CrawlCommandTests {
    @Test("Crawl single Apple documentation page", .tags(.integration))
    @MainActor
    func crawlSinglePage() async throws {
        // Set up NSApplication for WKWebView
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-crawl-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(forceRecrawl: true),
            output: Shared.OutputConfiguration(format: .markdown)
        )

        print("🧪 Test: Crawl single page")
        print("   URL: \(config.crawler.startURL)")

        let crawler = await Core.Crawler(configuration: config)
        let stats = try await crawler.crawl()

        // Verify stats
        #expect(stats.totalPages == 1, "Should have crawled exactly 1 page")
        #expect(stats.newPages == 1, "Should have 1 new page")
        #expect(stats.errors == 0, "Should have no errors")

        // Verify output directory exists
        var isDirectory: ObjCBool = false
        let dirExists = FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDirectory)
        #expect(dirExists && isDirectory.boolValue, "Output directory should exist")

        // Verify markdown file was created
        let markdownFiles = findMarkdownFiles(in: tempDir)
        #expect(!markdownFiles.isEmpty, "Should have created markdown files")

        if let firstFile = markdownFiles.first {
            let content = try String(contentsOf: firstFile, encoding: .utf8)
            #expect(content.count > 100, "Markdown content should be substantial")
            #expect(content.contains("Swift"), "Content should mention Swift")
            print("   ✅ Created: \(firstFile.lastPathComponent) (\(content.count) chars)")
        }

        // Verify metadata.json was created
        let metadataFile = tempDir.appendingPathComponent("metadata.json")
        #expect(FileManager.default.fileExists(atPath: metadataFile.path), "Metadata should exist")

        let metadata = try CrawlMetadata.load(from: metadataFile)
        #expect(!metadata.pages.isEmpty, "Metadata should contain pages")
        #expect(metadata.stats.totalPages == 1, "Metadata stats should match")

        print("   ✅ Crawl test passed!")
    }

    @Test("Crawl with resume capability", .tags(.integration))
    @MainActor
    func crawlWithResume() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-resume-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(enabled: true, forceRecrawl: false),
            output: Shared.OutputConfiguration(format: .markdown)
        )

        print("🧪 Test: Crawl with resume")

        // First crawl
        let crawler1 = await Core.Crawler(configuration: config)
        let stats1 = try await crawler1.crawl()
        #expect(stats1.newPages == 1, "First crawl should have 1 new page")

        // Second crawl (should skip unchanged)
        let crawler2 = await Core.Crawler(configuration: config)
        let stats2 = try await crawler2.crawl()
        #expect(stats2.skippedPages == 1, "Second crawl should skip unchanged page")
        #expect(stats2.newPages == 0, "Second crawl should have no new pages")

        print("   ✅ Resume test passed!")
    }

    @Test("Crawl Swift Evolution proposal", .tags(.integration))
    @MainActor
    func crawlSwiftEvolution() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-evolution-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Crawl Swift Evolution proposal")

        let crawler = Core.EvolutionCrawler(
            outputDirectory: tempDir,
            onlyAccepted: true
        )

        _ = try await crawler.crawl()

        // Verify markdown file exists
        let markdownFiles = findMarkdownFiles(in: tempDir)
        #expect(!markdownFiles.isEmpty, "Should have created markdown files")

        if let firstFile = markdownFiles.first {
            let content = try String(contentsOf: firstFile, encoding: .utf8)
            #expect(content.contains("SE-"), "Content should contain SE- proposal number")
            print("   ✅ Downloaded: \(firstFile.lastPathComponent)")
        }

        print("   ✅ Evolution crawl test passed!")
    }
}

// MARK: - Helper Functions

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
