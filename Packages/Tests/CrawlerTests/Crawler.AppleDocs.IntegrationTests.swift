import AppKit
@testable import Core
import CoreProtocols
import Crawler
import CrawlerModels
import Foundation
import LoggingModels
import SharedConfiguration
import SharedConstants
@testable import SharedCore
import SharedModels
import Testing
import TestSupport

// Extracted from CupertinoCoreTests during the #394 Core DI leaf
// (extracts every test that touches `Crawler.AppleDocs` or
// `Crawler.AppleDocs.State` into the Crawler target's test
// neighbourhood, so CoreTests no longer needs a `Crawler` dep).
//
// Contents:
// - downloadRealAppleDocPage integration test (tagged .integration —
//   requires network; off by default in CI)
// - 13 Crawler.AppleDocs.State change-detection tests
// - private test helpers (createTempDirectory, createTestConfiguration,
//   verifyOutputDirectory, verifyMarkdownFiles, etc.)
//
// The helpers stay file-private here so the same shape used in
// CupertinoCoreTests pre-extraction is preserved verbatim. No
// behavioural change.

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

    let crawler = await Crawler.AppleDocs(
        configuration: config,
        htmlParser: LiveTestHTMLParserStrategy(),
        appleJSONParser: LiveTestAppleJSONParserStrategy(),
        priorityPackageStrategy: LiveTestPriorityPackageStrategy(),
            logger: Logging.NoopRecording()
    )
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
        crawler: Shared.Configuration.Crawler(
            startURL: URL(string: "https://developer.apple.com/documentation/swift")!,
            maxPages: 1,
            maxDepth: 1,
            outputDirectory: outputDirectory
        ),
        changeDetection: Shared.Configuration.ChangeDetection(forceRecrawl: true, outputDirectory: URL(fileURLWithPath: "/tmp/cupertino-integration-test")),
        output: Shared.Configuration.Output(format: .markdown)
    )
}

private func logTestStart(config: Shared.Configuration) {
    print("🧪 Integration Test: Downloading real Apple doc page...")
    print("   URL: \(config.crawler.startURL)")
    print("   Output: \(config.crawler.outputDirectory.path)")
}

private func verifyBasicStats(_ stats: Shared.Models.CrawlStatistics) throws {
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
        let metadata = try Shared.Models.CrawlMetadata.load(from: metadataFile)
        #expect(!metadata.pages.isEmpty, "Metadata should contain page information")
        print("   ✅ Metadata created with \(metadata.pages.count) page(s)")
    }
}

// MARK: - Crawler.AppleDocs.State Change Detection Tests

@Test("Crawler.AppleDocs.State initializes with empty metadata")
func crawlerStateInitialization() async {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false,
        outputDirectory: tempDir
    )

    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())
    let pageCount = await state.getPageCount()

    #expect(pageCount == 0)
    print("   ✅ Crawler.AppleDocs.State initialized with empty metadata")
}

@Test("Crawler.AppleDocs.State loads existing metadata on initialization")
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
    var metadata = Shared.Models.CrawlMetadata()
    metadata.pages["https://example.com/doc1"] = Shared.Models.PageMetadata(
        url: "https://example.com/doc1",
        framework: "test",
        filePath: doc1Path.path,
        contentHash: "hash1",
        depth: 0
    )
    metadata.pages["https://example.com/doc2"] = Shared.Models.PageMetadata(
        url: "https://example.com/doc2",
        framework: "test",
        filePath: doc2Path.path,
        contentHash: "hash2",
        depth: 1
    )
    try metadata.save(to: metadataFile)

    // Initialize state - should load existing metadata
    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false,
        outputDirectory: tempDir
    )
    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())
    let pageCount = await state.getPageCount()

    #expect(pageCount == 2)
    print("   ✅ Crawler.AppleDocs.State loaded existing metadata with \(pageCount) pages")
}

@Test("Crawler.AppleDocs.State shouldRecrawl detects new pages")
func crawlerStateShouldRecrawlNewPage() async {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false,
        outputDirectory: tempDir
    )

    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    // New page should be recrawled
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/new-page",
        contentHash: "hash123",
        filePath: URL(fileURLWithPath: "/test/new.md")
    )

    #expect(shouldRecrawl)
    print("   ✅ New page correctly identified for crawling")
}

@Test("Crawler.AppleDocs.State shouldRecrawl detects content changes")
func crawlerStateShouldRecrawlContentChanged() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("doc.md")

    // Create file and metadata
    try "Original content".write(to: outputFile, atomically: true, encoding: .utf8)

    var metadata = Shared.Models.CrawlMetadata()
    metadata.pages["https://example.com/doc"] = Shared.Models.PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "old-hash",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false,
        outputDirectory: tempDir
    )
    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    // Same URL but different hash should trigger recrawl
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "new-hash",
        filePath: outputFile
    )

    #expect(shouldRecrawl)
    print("   ✅ Content change correctly detected")
}

@Test("Crawler.AppleDocs.State shouldRecrawl skips unchanged pages")
func crawlerStateShouldRecrawlSkipsUnchanged() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("doc.md")

    // Create file and metadata
    try "Content".write(to: outputFile, atomically: true, encoding: .utf8)

    var metadata = Shared.Models.CrawlMetadata()
    metadata.pages["https://example.com/doc"] = Shared.Models.PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "same-hash",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false,
        outputDirectory: tempDir
    )
    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    // Same URL, same hash, file exists - should skip
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "same-hash",
        filePath: outputFile
    )

    #expect(!shouldRecrawl)
    print("   ✅ Unchanged page correctly skipped")
}

@Test("Crawler.AppleDocs.State shouldRecrawl detects missing files")
func crawlerStateShouldRecrawlMissingFile() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("missing.md")

    // Create metadata but NOT the file
    var metadata = Shared.Models.CrawlMetadata()
    metadata.pages["https://example.com/doc"] = Shared.Models.PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "hash123",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false,
        outputDirectory: tempDir
    )
    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    // File missing should trigger recrawl
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "hash123",
        filePath: outputFile
    )

    #expect(shouldRecrawl)
    print("   ✅ Missing file correctly detected")
}

@Test("Crawler.AppleDocs.State respects forceRecrawl flag")
func crawlerStateForceRecrawl() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("doc.md")

    // Create file and metadata
    try "Content".write(to: outputFile, atomically: true, encoding: .utf8)

    var metadata = Shared.Models.CrawlMetadata()
    metadata.pages["https://example.com/doc"] = Shared.Models.PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "same-hash",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: true, // Force recrawl
        outputDirectory: tempDir
    )
    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    // Even with same hash and existing file, should recrawl when forced
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "same-hash",
        filePath: outputFile
    )

    #expect(shouldRecrawl)
    print("   ✅ forceRecrawl flag correctly enforced")
}

@Test("Crawler.AppleDocs.State respects disabled change detection")
func crawlerStateDisabledChangeDetection() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let outputFile = tempDir.appendingPathComponent("doc.md")

    // Create file and metadata
    try "Content".write(to: outputFile, atomically: true, encoding: .utf8)

    var metadata = Shared.Models.CrawlMetadata()
    metadata.pages["https://example.com/doc"] = Shared.Models.PageMetadata(
        url: "https://example.com/doc",
        framework: "test",
        filePath: outputFile.path,
        contentHash: "same-hash",
        depth: 0
    )
    try metadata.save(to: metadataFile)

    let config = Shared.Configuration.ChangeDetection(
        enabled: false, // Disabled
        metadataFile: metadataFile,
        forceRecrawl: false,
        outputDirectory: tempDir
    )
    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    // With change detection disabled, should always recrawl
    let shouldRecrawl = await state.shouldRecrawl(
        url: "https://example.com/doc",
        contentHash: "same-hash",
        filePath: outputFile
    )

    #expect(shouldRecrawl)
    print("   ✅ Disabled change detection correctly handled")
}

@Test("Crawler.AppleDocs.State updatePage adds page metadata")
func crawlerStateUpdatePage() async {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false,
        outputDirectory: tempDir
    )

    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

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

@Test("Crawler.AppleDocs.State updateStatistics modifies stats")
func crawlerStateUpdateStatistics() async {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false,
        outputDirectory: tempDir
    )

    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

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

@Test("Crawler.AppleDocs.State session state management")
func crawlerStateSessionManagement() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: tempDir.appendingPathComponent("metadata.json"),
        forceRecrawl: false,
        outputDirectory: tempDir
    )

    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    // Initially no active session
    let hasActiveSession1 = await state.hasActiveSession()
    #expect(!hasActiveSession1)

    // Save session state
    let visited = Set(["https://example.com/1", "https://example.com/2"])
    let queue = try [
        (url: #require(URL(string: "https://example.com/3")), depth: 1),
        (url: #require(URL(string: "https://example.com/4")), depth: 2),
    ]

    try await state.saveSessionState(
        visited: visited,
        queue: queue,
        startURL: #require(URL(string: "https://example.com/start")),
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

@Test("Crawler.AppleDocs.State finalizeCrawl saves metadata")
func crawlerStateFinalizeAndSave() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false,
        outputDirectory: tempDir
    )

    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    // Update some data
    await state.updatePage(
        url: "https://example.com/doc",
        framework: "swift",
        filePath: "/test/doc.md",
        contentHash: "hash123",
        depth: 0
    )

    let stats = Shared.Models.CrawlStatistics(
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
    let loadedMetadata = try Shared.Models.CrawlMetadata.load(from: metadataFile)
    #expect(loadedMetadata.pages.count == 1)
    #expect(loadedMetadata.stats.totalPages == 5)
    #expect(loadedMetadata.lastCrawl != nil)

    print("   ✅ Metadata finalized and saved correctly")
}

@Test("Crawler.AppleDocs.State autoSaveIfNeeded respects interval")
func crawlerStateAutoSaveInterval() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let metadataFile = tempDir.appendingPathComponent("metadata.json")
    let config = Shared.Configuration.ChangeDetection(
        enabled: true,
        metadataFile: metadataFile,
        forceRecrawl: false,
        outputDirectory: tempDir
    )

    let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

    let visited = Set(["https://example.com/1"])
    let queue = try [(url: #require(URL(string: "https://example.com/2")), depth: 1)]
    let startURL = try #require(URL(string: "https://example.com/start"))

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
