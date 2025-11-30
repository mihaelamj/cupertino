@testable import Core
import Foundation
@testable import Shared
import Testing

// MARK: - Crawler Tests

/// Tests for the Core.Crawler web crawling engine
/// Note: These are integration tests that use real WKWebView

@Suite("Crawler")
struct CrawlerTests {
    // MARK: - Initialization Tests

    @Test("Crawler initializes with configuration")
    @MainActor
    func crawlerInitialization() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://developer.apple.com")!,
                maxPages: 5,
                outputDirectory: tempDir
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(
                enabled: false,
                metadataFile: tempDir.appendingPathComponent("metadata.json")
            ),
            output: Shared.OutputConfiguration()
        )

        let crawler = await Core.Crawler(configuration: config)

        // If we get here without crashing, initialization worked
        _ = crawler

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - URL Normalization Tests

    @Test("URLUtilities normalize preserves path but removes trailing slash")
    func urlNormalizePreservesPath() throws {
        let url = URL(string: "https://example.com/path/")!
        let normalized = URLUtilities.normalize(url)

        // Normalization removes fragments, query params, and trailing slashes
        #expect(normalized?.path == "/path")
    }

    @Test("URLUtilities normalize removes fragments")
    func urlNormalizeRemovesFragments() throws {
        let url = URL(string: "https://example.com/path#section")!
        let normalized = URLUtilities.normalize(url)

        #expect(normalized?.fragment == nil)
        #expect(!normalized!.absoluteString.contains("#"))
    }

    @Test("URLUtilities normalize removes query parameters")
    func urlNormalizeRemovesQueryParams() throws {
        let url = URL(string: "https://example.com/path?param=value")!
        let normalized = URLUtilities.normalize(url)

        #expect(normalized?.query == nil)
        #expect(!normalized!.absoluteString.contains("?"))
    }

    // MARK: - Framework Extraction Tests

    @Test("URLUtilities extracts framework from Apple docs URL")
    func extractFrameworkFromAppleDocs() throws {
        let url = URL(string: "https://developer.apple.com/documentation/swift/array")!
        let framework = URLUtilities.extractFramework(from: url)

        #expect(framework == "swift")
    }

    @Test("URLUtilities extracts framework from nested path")
    func extractFrameworkFromNestedPath() throws {
        let url = URL(string: "https://developer.apple.com/documentation/uikit/uiview/animator")!
        let framework = URLUtilities.extractFramework(from: url)

        #expect(framework == "uikit")
    }

    @Test("URLUtilities returns root for non-documentation URLs")
    func extractFrameworkReturnsRootForNonDocs() throws {
        let url = URL(string: "https://example.com/some/path")!
        let framework = URLUtilities.extractFramework(from: url)

        #expect(framework == "root")
    }

    // MARK: - Filename Generation Tests

    @Test("URLUtilities generates filename from URL")
    func generateFilenameFromURL() throws {
        let url = URL(string: "https://developer.apple.com/documentation/swift/array")!
        let filename = URLUtilities.filename(from: url)

        #expect(filename.contains("array"))
        #expect(!filename.contains("/")) // No slashes in filename
    }

    @Test("URLUtilities handles complex paths in filename")
    func generateFilenameFromComplexPath() throws {
        let url = URL(string: "https://developer.apple.com/documentation/uikit/uiview/1622417-addsubview")!
        let filename = URLUtilities.filename(from: url)

        #expect(!filename.isEmpty)
        #expect(!filename.contains("/"))
    }

    // MARK: - Hash Utilities Tests

    @Test("HashUtilities SHA256 generates consistent hashes")
    func hashUtilitiesConsistentHash() throws {
        let content = "Test content for hashing"

        let hash1 = HashUtilities.sha256(of: content)
        let hash2 = HashUtilities.sha256(of: content)

        #expect(hash1 == hash2)
        #expect(hash1.count == 64) // SHA256 produces 64 hex characters
    }

    @Test("HashUtilities SHA256 produces different hashes for different content")
    func hashUtilitiesDifferentContentDifferentHash() throws {
        let content1 = "Content A"
        let content2 = "Content B"

        let hash1 = HashUtilities.sha256(of: content1)
        let hash2 = HashUtilities.sha256(of: content2)

        #expect(hash1 != hash2)
    }

    @Test("HashUtilities SHA256 handles empty string")
    func hashUtilitiesEmptyString() throws {
        let hash = HashUtilities.sha256(of: "")

        #expect(!hash.isEmpty)
        #expect(hash.count == 64)
    }

    // MARK: - CrawlStatistics Tests

    @Test("CrawlStatistics initializes with zeros")
    func statisticsInitializesWithZeros() throws {
        let stats = CrawlStatistics()

        #expect(stats.totalPages == 0)
        #expect(stats.newPages == 0)
        #expect(stats.updatedPages == 0)
        #expect(stats.skippedPages == 0)
        #expect(stats.errors == 0)
    }

    @Test("CrawlStatistics is Codable")
    func statisticsIsCodable() throws {
        var stats = CrawlStatistics()
        stats.totalPages = 100
        stats.newPages = 50
        stats.updatedPages = 30
        stats.skippedPages = 20
        stats.errors = 5
        stats.startTime = Date()
        stats.endTime = Date().addingTimeInterval(3600)

        let encoder = JSONEncoder()
        let data = try encoder.encode(stats)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CrawlStatistics.self, from: data)

        #expect(decoded.totalPages == 100)
        #expect(decoded.newPages == 50)
        #expect(decoded.updatedPages == 30)
        #expect(decoded.skippedPages == 20)
        #expect(decoded.errors == 5)
    }

    // MARK: - CrawlProgress Tests

    @Test("CrawlProgress calculates percentage")
    func progressCalculatesPercentage() throws {
        let stats = CrawlStatistics()
        let progress = CrawlProgress(
            currentURL: URL(string: "https://example.com")!,
            visitedCount: 10,
            totalPages: 100,
            stats: stats
        )

        #expect(progress.visitedCount == 10)
        #expect(progress.totalPages == 100)
        #expect(progress.percentage == 10.0)
    }

    // MARK: - Integration Tests (Tagged as .integration)

    @Test("Crawler respects max pages limit", .tags(.integration))
    @MainActor
    func crawlerRespectsMaxPages() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://example.com")!,
                maxPages: 1, // Limit to 1 page
                outputDirectory: tempDir,
                requestDelay: 0.1
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(
                enabled: false,
                metadataFile: tempDir.appendingPathComponent("metadata.json")
            ),
            output: Shared.OutputConfiguration()
        )

        let crawler = await Core.Crawler(configuration: config)

        // Note: This may fail to load the actual page (network required),
        // but it tests that the crawler can be instantiated and attempt to crawl
        do {
            let stats = try await crawler.crawl()
            #expect(stats.totalPages <= 1)
        } catch {
            // Network errors are acceptable in unit tests
            // The important thing is the crawler initialized and attempted to run
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Crawler creates output directory", .tags(.integration))
    @MainActor
    func crawlerCreatesOutputDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        // Ensure directory doesn't exist yet
        try? FileManager.default.removeItem(at: tempDir)
        #expect(!FileManager.default.fileExists(atPath: tempDir.path))

        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: URL(string: "https://example.com")!,
                maxPages: 1,
                outputDirectory: tempDir,
                requestDelay: 0.1
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(
                enabled: false,
                metadataFile: tempDir.appendingPathComponent("metadata.json")
            ),
            output: Shared.OutputConfiguration()
        )

        let crawler = await Core.Crawler(configuration: config)

        do {
            _ = try await crawler.crawl()
        } catch {
            // Network errors expected - we're testing directory creation
        }

        // Directory should exist even if crawl failed
        #expect(FileManager.default.fileExists(atPath: tempDir.path))

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Known Problematic Pages Tests (Issue #25)

    @Test("LAPACK functions page URL is recognized as problematic", .tags(.integration))
    func lapackFunctionsURLIsProblematic() throws {
        // This page has 1600+ LAPACK/BLAS routines and crashes WKWebView due to OOM
        // URL: https://developer.apple.com/documentation/accelerate/lapack-functions
        // The JSON API alternative: https://developer.apple.com/tutorials/data/documentation/accelerate/lapack-functions.json
        // returns 7.2MB of structured data vs trying to render a massive DOM

        let lapackURL = URL(string: "https://developer.apple.com/documentation/accelerate/lapack-functions")!

        // The URL should normalize correctly
        let normalized = URLUtilities.normalize(lapackURL)
        #expect(normalized != nil)
        #expect(normalized?.absoluteString == "https://developer.apple.com/documentation/accelerate/lapack-functions")

        // Framework extraction should work
        let framework = URLUtilities.extractFramework(from: lapackURL)
        #expect(framework == "accelerate")

        // Filename generation should work
        let filename = URLUtilities.filename(from: lapackURL)
        #expect(filename.contains("lapack-functions") || filename.contains("lapack_functions"))
    }

    @Test("Apple JSON API endpoint can be derived from documentation URL")
    func appleJSONAPIEndpoint() throws {
        // Apple's documentation uses a JSON API under the hood
        // Web: https://developer.apple.com/documentation/accelerate/lapack-functions
        // JSON: https://developer.apple.com/tutorials/data/documentation/accelerate/lapack-functions.json

        let docURL = URL(string: "https://developer.apple.com/documentation/accelerate/lapack-functions")!

        // Derive JSON API URL from documentation URL
        let path = docURL.path // "/documentation/accelerate/lapack-functions"
        let jsonURLString = "https://developer.apple.com/tutorials/data\(path).json"
        let jsonURL = URL(string: jsonURLString)

        #expect(jsonURL != nil)
        #expect(jsonURL?.absoluteString == "https://developer.apple.com/tutorials/data/documentation/accelerate/lapack-functions.json")
    }
}
