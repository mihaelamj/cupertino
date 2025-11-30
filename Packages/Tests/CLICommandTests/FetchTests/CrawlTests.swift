import AppKit
@testable import CLI
@testable import Core
import Foundation
@testable import Search
@testable import Shared
import Testing
import TestSupport

// MARK: - Web Crawl Tests

/// Tests for the `cupertino fetch` command (web crawling)
/// Verifies web crawling functionality, resume capability, and Evolution proposals

@Suite("Web Crawl Tests")
struct WebCrawlTests {
    @Test("Fetch single Apple documentation page", .tags(.integration))
    @MainActor
    func fetchSinglePage() async throws {
        // Set up NSApplication for WKWebView
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-fetch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
                maxPages: 1,
                maxDepth: 0,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(forceRecrawl: true, outputDirectory: tempDir),
            output: Shared.OutputConfiguration(format: .markdown)
        )

        print("🧪 Test: Fetch single page")
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

        // Verify documentation file was created (JSON or markdown)
        let docFiles = findDocumentFiles(in: tempDir)
        #expect(!docFiles.isEmpty, "Should have created documentation files")

        if let firstFile = docFiles.first {
            let content = try String(contentsOf: firstFile, encoding: .utf8)
            #expect(content.count > 100, "Documentation content should be substantial")
            #expect(content.lowercased().contains("swift"), "Content should mention Swift")
            print("   ✅ Created: \(firstFile.lastPathComponent) (\(content.count) chars)")
        }

        // Verify metadata.json was created
        let metadataFile = tempDir.appendingPathComponent("metadata.json")
        #expect(FileManager.default.fileExists(atPath: metadataFile.path), "Metadata should exist")

        let metadata = try CrawlMetadata.load(from: metadataFile)
        #expect(!metadata.pages.isEmpty, "Metadata should contain pages")
        #expect(metadata.stats.totalPages == 1, "Metadata stats should match")

        print("   ✅ Fetch test passed!")
    }

    @Test("Fetch with resume capability", .tags(.integration))
    @MainActor
    func fetchWithResume() async throws {
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
            changeDetection: Shared.ChangeDetectionConfiguration(
                enabled: true,
                forceRecrawl: false,
                outputDirectory: tempDir
            ),
            output: Shared.OutputConfiguration(format: .markdown)
        )

        print("🧪 Test: Fetch with resume")

        // First fetch
        let crawler1 = await Core.Crawler(configuration: config)
        let stats1 = try await crawler1.crawl()
        #expect(stats1.newPages == 1, "First fetch should have 1 new page")

        // Second fetch (should skip unchanged)
        let crawler2 = await Core.Crawler(configuration: config)
        let stats2 = try await crawler2.crawl()
        #expect(stats2.skippedPages == 1, "Second fetch should skip unchanged page")
        #expect(stats2.newPages == 0, "Second fetch should have no new pages")

        print("   ✅ Resume test passed!")
    }

    @Test("Fetch Swift Evolution proposal", .tags(.integration))
    @MainActor
    func fetchSwiftEvolution() async throws {
        _ = NSApplication.shared

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-evolution-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        print("🧪 Test: Fetch Swift Evolution proposal")

        let crawler = Core.EvolutionCrawler(
            outputDirectory: tempDir,
            onlyAccepted: true
        )

        _ = try await crawler.crawl(limit: 3)

        // Verify markdown file exists
        let markdownFiles = findMarkdownFiles(in: tempDir)
        #expect(!markdownFiles.isEmpty, "Should have created markdown files")

        if let firstFile = markdownFiles.first {
            let content = try String(contentsOf: firstFile, encoding: .utf8)
            #expect(content.contains("SE-"), "Content should contain SE- proposal number")
            print("   ✅ Downloaded: \(firstFile.lastPathComponent)")
        }

        print("   ✅ Evolution fetch test passed!")
    }
}

// MARK: - Helper Functions

/// Find documentation files (JSON preferred, then markdown)
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
