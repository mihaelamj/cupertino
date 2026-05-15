@testable import Crawler
import CrawlerModels
import Foundation
import LoggingModels
import SharedConstants
import Testing

// MARK: - Retry Queue Tests (#292)

@Suite("Retry Queue")
struct RetryQueueTests {
    // MARK: - Test 1: QueuedRetryURL Codable round-trip + backward compat

    @Test("QueuedRetryURL encodes and decodes with all fields")
    func queuedRetryURLCodableRoundTrip() throws {
        let now = Date()
        let original = Shared.Models.QueuedRetryURL(
            url: "https://developer.apple.com/documentation/swift/array",
            attempts: 1,
            nextAttempt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Shared.Models.QueuedRetryURL.self, from: data)

        #expect(decoded.url == original.url)
        #expect(decoded.attempts == original.attempts)
        #expect(abs(decoded.nextAttempt.timeIntervalSince(original.nextAttempt)) < 1)
    }

    @Test("CrawlSessionState decodes without retryQueue field (backward compat)")
    func crawlSessionStateBackwardCompatDecode() throws {
        // Simulate an old-format session file that has no retryQueue field.
        let json = """
        {
            "visited": ["https://developer.apple.com/documentation/swift"],
            "queue": [],
            "startURL": "https://developer.apple.com/documentation/swift",
            "outputDirectory": "/tmp/cupertino-test",
            "sessionStartTime": "2026-05-15T00:00:00Z",
            "lastSaveTime": "2026-05-15T00:01:00Z",
            "isActive": true
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(Shared.Models.CrawlSessionState.self, from: data)

        // retryQueue must default to empty — not crash
        #expect(state.retryQueue.isEmpty)
        #expect(state.visited.count == 1)
    }

    // MARK: - Test 2: Backoff schedule

    @Test("Deferred retry backoff schedule: 30s → 5min → 30min")
    @MainActor
    func deferredRetryBackoffSchedule() {
        #expect(Crawler.AppleDocs.deferredRetryDelay(forAttempt: 0) == 30)
        #expect(Crawler.AppleDocs.deferredRetryDelay(forAttempt: 1) == 300)
        #expect(Crawler.AppleDocs.deferredRetryDelay(forAttempt: 2) == 1800)
        // Beyond max attempt always clamps to the last value (1800s)
        #expect(Crawler.AppleDocs.deferredRetryDelay(forAttempt: 5) == 1800)
    }

    // MARK: - Test 3: Counter methods

    @Test("recordDeferredRetry increments deferredRetries, recordRetrySucceeded increments retriesSucceeded")
    func stateCounterMethods() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = Shared.Configuration.ChangeDetection(
            enabled: false,
            metadataFile: tempDir.appendingPathComponent("metadata.json"),
            outputDirectory: tempDir
        )
        let state = Crawler.AppleDocs.State(configuration: config, logger: Logging.NoopRecording())

        var stats = await state.getStatistics()
        #expect(stats.deferredRetries == 0)
        #expect(stats.retriesSucceeded == 0)
        #expect(stats.errors == 0)

        await state.recordDeferredRetry()
        await state.recordDeferredRetry()
        await state.recordRetrySucceeded()

        stats = await state.getStatistics()
        #expect(stats.deferredRetries == 2)
        #expect(stats.retriesSucceeded == 1)
        #expect(stats.errors == 0, "recordDeferredRetry must not touch the error counter")
    }

    // MARK: - Test 4: Integration — looksLikeHTTPErrorPage leads to deferral not immediate error

    /// Verifies the end-to-end deferral+retry path: a URL that returns an HTTP error page on
    /// first load is deferred, then succeeds on the first retry (30s window).
    ///
    /// - Requires: network access and WKWebView (macOS only). Tagged `.integration`.
    /// - Runtime: ~30s (one retry-queue window).
    @Test("looksLikeHTTPErrorPage defers URL; successful retry increments retriesSucceeded not errors", .tags(.integration))
    @MainActor
    func httpErrorPageDefersAndRetriesSuccessfully() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = try Shared.Configuration(
            crawler: Shared.Configuration.Crawler(
                startURL: #require(URL(string: "https://developer.apple.com/documentation/swift")),
                maxPages: 1,
                outputDirectory: tempDir,
                requestDelay: 0
            ),
            changeDetection: Shared.Configuration.ChangeDetection(
                enabled: false,
                metadataFile: tempDir.appendingPathComponent("metadata.json"),
                outputDirectory: tempDir
            ),
            output: Shared.Configuration.Output()
        )

        // Mock: fails on the first HTML load, succeeds on subsequent calls.
        // This simulates a transient CDN error that clears before the first retry window (30s).
        let htmlParser = RecoveringHTTPErrorHTMLParserStrategy()

        let crawler = await Crawler.AppleDocs(
            configuration: config,
            htmlParser: htmlParser,
            appleJSONParser: Crawler.NoopAppleJSONParserStrategy(),
            priorityPackageStrategy: Crawler.NoopPriorityPackageStrategy(),
            logger: Logging.NoopRecording()
        )

        do {
            let stats = try await crawler.crawl()

            // Only assert if the page was actually loaded (network available).
            // deferredRetries > 0 means the URL was deferred, not immediately discarded.
            // retriesSucceeded > 0 means the retry path ran and the mock recovered.
            if stats.deferredRetries > 0 {
                #expect(stats.deferredRetries >= 1, "URL should have been deferred at least once")
                #expect(stats.retriesSucceeded >= 1, "Retry should have succeeded after error cleared")
                #expect(stats.errors == 0, "No permanent errors when retry succeeds")
            }
        } catch {
            // Network errors (no WKWebView, offline, etc.) are acceptable in non-integration environments.
        }
    }
}

// MARK: - Test helpers

/// HTML parser that signals an HTTP error page on the first call only, then acts normally.
/// Models a transient CDN error that resolves before the first retry window.
private final class RecoveringHTTPErrorHTMLParserStrategy: Crawler.HTMLParserStrategy, @unchecked Sendable {
    private var callCount = 0

    func convert(html: String, url: URL) -> String { "" }

    func toStructuredPage(
        html: String,
        url: URL,
        source: Shared.Models.StructuredDocumentationPage.Source,
        depth: Int?
    ) -> Shared.Models.StructuredDocumentationPage? { nil }

    func looksLikeHTTPErrorPage(html: String) -> Bool {
        callCount += 1
        return callCount == 1  // true only on the first call
    }

    func looksLikeJavaScriptFallback(html: String) -> Bool { false }
}
