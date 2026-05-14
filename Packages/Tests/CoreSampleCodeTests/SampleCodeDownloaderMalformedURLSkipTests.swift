@testable import CoreSampleCode
import Foundation
import LoggingModels
import SharedConstants
import Testing

// Covers the malformed-URL skip path added to
// `Core.Sample.Core.Downloader.downloadSample` in PR #288. The skip fires
// when a row from Apple's sample-code catalog has a `sample.url` that
// `URL(string:)` can't parse. The previous force-unwrap form would
// crash on the same input.
//
// PR #288 also reorders the guard to happen BEFORE `createWebView()`,
// so the test never has to stand up a WKWebView — the guard short-
// circuits with `stats.errors += 1` first.

@Suite("Sample.Core.Downloader.downloadSample malformed-URL skip", .serialized)
struct SampleCodeDownloaderMalformedURLSkipTests {
    private func tempOutputDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-sample-skip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Empty sample.url increments stats.errors + stats.totalSamples and returns without WebKit")
    @MainActor
    func emptyURLBumpsErrorsCounter() async throws {
        let outputDir = try tempOutputDirectory()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let downloader = Sample.Core.Downloader(outputDirectory: outputDir, logger: Logging.NoopRecording())
        var stats = Sample.Core.Statistics()
        let badSample = SampleMetadata(name: "Bad Sample", url: "", slug: "bad-sample")

        // If the guard fires before createWebView (the PR #288 ordering),
        // this call returns cleanly. If a future edit moves the guard
        // back after createWebView, the test still works on macOS where
        // WKWebView allocation succeeds — but the perf savings disappear,
        // and that's worth catching in review.
        try await downloader.downloadSample(badSample, stats: &stats)

        #expect(stats.errors == 1, "Malformed URL row should bump errors")
        #expect(stats.totalSamples == 1, "Malformed URL row still counts toward totalSamples")
        #expect(stats.skippedSamples == 0, "Skip-due-to-malformed-URL is not the same as already-exists skip")
        #expect(stats.downloadedSamples == 0, "Nothing should have been downloaded")
    }

    @Test("A whitespace-only sample.url that fails URL(string:) is also skipped")
    @MainActor
    func whitespaceURLFailsParseAndIsSkipped() async throws {
        // Sanity: URL(string:) does fail on a string with an embedded
        // space inside what would be the scheme — pin that here so the
        // test isn't silently doing nothing if the URL parser becomes
        // more permissive.
        #expect(URL(string: "ht tp://x") == nil)

        let outputDir = try tempOutputDirectory()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let downloader = Sample.Core.Downloader(outputDirectory: outputDir, logger: Logging.NoopRecording())
        var stats = Sample.Core.Statistics()
        let badSample = SampleMetadata(name: "Bad Sample 2", url: "ht tp://x", slug: "bad-sample-2")

        try await downloader.downloadSample(badSample, stats: &stats)

        #expect(stats.errors == 1)
        #expect(stats.totalSamples == 1)
    }

    @Test("Two malformed rows in sequence accumulate errors and totalSamples")
    @MainActor
    func twoMalformedRowsAccumulate() async throws {
        let outputDir = try tempOutputDirectory()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let downloader = Sample.Core.Downloader(outputDirectory: outputDir, logger: Logging.NoopRecording())
        var stats = Sample.Core.Statistics()

        try await downloader.downloadSample(
            SampleMetadata(name: "A", url: "", slug: "a"),
            stats: &stats
        )
        try await downloader.downloadSample(
            SampleMetadata(name: "B", url: "", slug: "b"),
            stats: &stats
        )

        #expect(stats.errors == 2)
        #expect(stats.totalSamples == 2)
        #expect(stats.skippedSamples == 0)
        #expect(stats.downloadedSamples == 0)
    }
}
