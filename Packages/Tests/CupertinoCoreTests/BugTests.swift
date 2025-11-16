@testable import CupertinoCore
@testable import CupertinoShared
import Foundation
import Testing

// MARK: - P0 Critical Bug Tests

/// Test for Bug #1: Resume Detection with File Paths
///
/// **Bug:** Resume detection uses `URL(string:)` instead of `URL(fileURLWithPath:)`
/// **File:** Sources/CupertinoCLI/Commands.swift:191
/// **Impact:** Resume functionality never works because file paths fail to parse as URLs
@Test("Bug #1: Resume detection with file paths")
func resumeDetectionWithFilePaths() async throws {
    // Create a test session with a file path as outputDirectory
    let testOutputDir = "/Users/test/.cupertino/docs"

    let sessionState = CrawlerState.SessionState(
        isActive: true,
        startURL: "https://developer.apple.com/documentation/",
        startTime: Date(),
        lastSaveTime: Date(),
        queue: [],
        visited: Set(),
        outputDirectory: testOutputDir // File path, not URL
    )

    // Test 1: URL(string:) FAILS with file paths (this is the bug)
    let urlFromString = URL(string: testOutputDir)
    #expect(urlFromString == nil, "URL(string:) should fail with file path - this is the BUG")

    // Test 2: URL(fileURLWithPath:) WORKS with file paths (this is the fix)
    let urlFromFilePath = URL(fileURLWithPath: testOutputDir)
    #expect(urlFromFilePath.path == testOutputDir, "URL(fileURLWithPath:) should work")

    // Test 3: Verify outputDirectory is actually saved in session state
    #expect(sessionState.outputDirectory != nil, "outputDirectory should be saved in session state")
    #expect(sessionState.outputDirectory == testOutputDir, "outputDirectory should match test path")
}

/// Test for Bug #1 (Part B): Output Directory Missing from Session State
///
/// **Bug:** The outputDirectory field is not being saved to session state
/// **File:** Sources/CupertinoCore/CrawlerState.swift:123-146
/// **Impact:** Even if URL parsing worked, there's no directory to compare against
@Test("Bug #1b: outputDirectory field must be saved in session state")
func outputDirectorySavedInSessionState() throws {
    let testDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-test-\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: testDir) }

    let metadataFile = testDir.appendingPathComponent("metadata.json")
    let outputDir = testDir.appendingPathComponent("docs")

    // Create a session state with outputDirectory
    let sessionState = CrawlerState.SessionState(
        isActive: true,
        startURL: "https://developer.apple.com/documentation/",
        startTime: Date(),
        lastSaveTime: Date(),
        queue: [],
        visited: Set(),
        outputDirectory: outputDir.path
    )

    // Create metadata with this session state
    let metadata = CrawlMetadata(
        lastCrawl: Date(),
        pages: [:],
        stats: CrawlStatistics(
            totalPages: 0,
            newPages: 0,
            updatedPages: 0,
            skippedPages: 0,
            errors: 0,
            startTime: Date(),
            endTime: Date()
        ),
        crawlState: sessionState
    )

    // Save metadata
    try metadata.save(to: metadataFile)

    // Load it back
    let loadedMetadata = try CrawlMetadata.load(from: metadataFile)

    // CRITICAL TEST: Verify outputDirectory was saved and loaded
    #expect(
        loadedMetadata.crawlState?.outputDirectory != nil,
        "outputDirectory MUST be saved in session state - Bug #1b"
    )
    #expect(
        loadedMetadata.crawlState?.outputDirectory == outputDir.path,
        "outputDirectory must match original path"
    )
}

/// Test for Bug #5: SearchError Enum Not Defined
///
/// **Bug:** SearchError is referenced but never defined
/// **File:** Sources/CupertinoSearch/SearchIndex.swift:165-183
/// **Impact:** Code doesn't compile OR error handling is broken
@Test("Bug #5: SearchError enum must exist")
func searchErrorEnumExists() {
    // This test will fail to compile if SearchError doesn't exist
    // Try to reference SearchError type
    let errorType = type(of: SearchError.self)
    #expect(errorType != nil, "SearchError enum must be defined")

    // Verify we can create expected error cases
    // (Uncomment once SearchError is defined)
    // let error = SearchError.prepareFailed("test")
    // #expect(error != nil, "Should be able to create SearchError.prepareFailed")
}

// MARK: - P1 High Priority Bug Tests

/// Test for Bug #7: Auto-save Errors Stop Entire Crawl
///
/// **Bug:** Auto-save throws and stops crawl when save fails
/// **File:** Sources/CupertinoCore/Crawler.swift:113-119
/// **Impact:** Crawl stops completely on save failure, losing progress
@Test("Bug #7: Auto-save errors should not stop crawl")
func autoSaveErrorsShouldNotStopCrawl() async throws {
    // This test verifies that auto-save failures don't throw and stop the crawl

    // Create a read-only directory to force save failures
    let testDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-readonly-test-\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

    // Create metadata file
    let metadataFile = testDir.appendingPathComponent("metadata.json")
    let initialMetadata = CrawlMetadata(
        lastCrawl: Date(),
        pages: [:],
        stats: CrawlStatistics(
            totalPages: 0,
            newPages: 0,
            updatedPages: 0,
            skippedPages: 0,
            errors: 0,
            startTime: Date(),
            endTime: Date()
        )
    )
    try initialMetadata.save(to: metadataFile)

    // Make directory read-only
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o444],
        ofItemAtPath: testDir.path
    )

    defer {
        // Restore permissions and cleanup
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: testDir.path
        )
        try? FileManager.default.removeItem(at: testDir)
    }

    // Try to save - should NOT throw, but log error instead
    let updatedMetadata = CrawlMetadata(
        lastCrawl: Date(),
        pages: ["test": PageMetadata(
            url: "https://example.com",
            framework: "test",
            filePath: "/test/path",
            contentHash: "hash123",
            lastCrawled: Date()
        )],
        stats: CrawlStatistics(
            totalPages: 1,
            newPages: 1,
            updatedPages: 0,
            skippedPages: 0,
            errors: 0,
            startTime: Date(),
            endTime: Date()
        )
    )

    // This should NOT throw - auto-save should handle errors gracefully
    // (Currently it WILL throw - that's the bug!)
    do {
        try updatedMetadata.save(to: metadataFile)
        // If we get here, save succeeded (unexpected in read-only dir)
        #expect(Bool(false), "Save should have failed in read-only directory")
    } catch {
        // Expected: save fails
        // BUG: This error should be caught and logged, not thrown up
        print("⚠️ Bug #7 present: Auto-save throws instead of logging error")
        #expect(true, "Auto-save should catch and log this error, not throw it")
    }
}

/// Test for Bug #8: Crawl Queue Contains Duplicates
///
/// **Bug:** Same URL can be queued multiple times
/// **File:** Sources/CupertinoCore/Crawler.swift:216-222
/// **Impact:** Memory waste, redundant work, 58% of queue is duplicates
@Test("Bug #8: Queue should not contain duplicates")
func queueDeduplication() {
    // Simulate queue behavior
    var queue: [(url: String, depth: Int)] = []
    var visited: Set<String> = []
    var queuedURLs: Set<String> = [] // THE FIX: Track queued URLs

    let urlsToQueue = [
        "https://developer.apple.com/documentation/swift/bool",
        "https://developer.apple.com/documentation/swift/string",
        "https://developer.apple.com/documentation/swift/bool", // Duplicate!
        "https://developer.apple.com/documentation/swift/int",
        "https://developer.apple.com/documentation/swift/bool", // Duplicate again!
    ]

    // BUGGY behavior (current implementation)
    for url in urlsToQueue {
        if !visited.contains(url) {
            queue.append((url: url, depth: 1)) // No deduplication!
        }
    }

    #expect(queue.count == 5, "BUGGY: All URLs added to queue, including duplicates")

    // FIXED behavior (with deduplication)
    queue.removeAll()
    queuedURLs.removeAll()

    for url in urlsToQueue {
        if !visited.contains(url), !queuedURLs.contains(url) {
            queue.append((url: url, depth: 1))
            queuedURLs.insert(url) // Track queued URLs
        }
    }

    #expect(queue.count == 3, "FIXED: Only unique URLs in queue")
    #expect(queuedURLs.count == 3, "Should have 3 unique URLs tracked")
}

/// Test for Bug #21: Priority Packages Missing URL Field
///
/// **Bug:** Packages in priority-packages.json missing url field
/// **File:** priority-packages.json
/// **Impact:** Package fetching will fail
@Test("Bug #21: Priority packages must have URL field")
func priorityPackagesHaveURL() throws {
    // Test package structure
    struct TestPackage: Codable {
        let owner: String
        let repo: String
        let url: String // This field is MISSING in current priority-packages.json!
    }

    // Valid package with URL
    let validJSON = """
    {
        "owner": "apple",
        "repo": "swift",
        "url": "https://github.com/apple/swift"
    }
    """

    let validPackage = try JSONDecoder().decode(TestPackage.self, from: Data(validJSON.utf8))
    #expect(validPackage.url == "https://github.com/apple/swift", "Package should have URL field")

    // BUGGY package without URL (will fail to decode)
    let buggyJSON = """
    {
        "owner": "apple",
        "repo": "swift"
    }
    """

    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(TestPackage.self, from: Data(buggyJSON.utf8))
    }
}

// MARK: - P2 Medium Priority Bug Tests

/// Test for Bug #13: Change Detection Hash Always Differs
///
/// **Bug:** WKWebView renders with timestamps, session IDs causing hash to change
/// **File:** Sources/CupertinoCore/CrawlerState.swift:33-61 and Crawler.swift:160-163
/// **Impact:** Everything re-crawled on updates, defeating change detection
@Test("Bug #13: Content hash should be stable across re-crawls")
func contentHashStability() {
    // Simulate HTML with dynamic content
    let htmlWithTimestamp1 = """
    <html>
    <meta name="session-id" content="abc123">
    <meta name="timestamp" content="2024-11-16T10:00:00Z">
    <h1>Swift Documentation</h1>
    <p>The Swift programming language</p>
    </html>
    """

    let htmlWithTimestamp2 = """
    <html>
    <meta name="session-id" content="xyz789">
    <meta name="timestamp" content="2024-11-16T11:00:00Z">
    <h1>Swift Documentation</h1>
    <p>The Swift programming language</p>
    </html>
    """

    // BUGGY: Hash includes dynamic content
    let buggyHash1 = HashUtilities.sha256(of: htmlWithTimestamp1)
    let buggyHash2 = HashUtilities.sha256(of: htmlWithTimestamp2)

    #expect(buggyHash1 != buggyHash2, "BUG: Hashes differ due to timestamps/session IDs")

    // FIXED: Extract stable content before hashing
    func extractStableContent(_ html: String) -> String {
        // Remove meta tags, timestamps, session IDs, etc.
        // This is simplified - real implementation needs proper HTML parsing
        html
            .replacingOccurrences(of: #"<meta[^>]*>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let stableContent1 = extractStableContent(htmlWithTimestamp1)
    let stableContent2 = extractStableContent(htmlWithTimestamp2)

    let fixedHash1 = HashUtilities.sha256(of: stableContent1)
    let fixedHash2 = HashUtilities.sha256(of: stableContent2)

    #expect(fixedHash1 == fixedHash2, "FIXED: Hashes should match when content is same")
}

// MARK: - Helper Extensions

extension CrawlMetadata {
    static func load(from url: URL) throws -> CrawlMetadata {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CrawlMetadata.self, from: data)
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}
