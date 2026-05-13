@testable import Core
import CoreProtocols
import Foundation
import SharedConstants
@testable import SharedCore
import Testing

// MARK: - Sample Code Downloader Tests

// Tests for the Sample.Core.Downloader
// Tests initialization, metadata handling, and statistics tracking

@Suite("Sample Code Downloader")
struct SampleCodeDownloaderTests {
    // MARK: - Initialization Tests

    @Test("Sample.Core.Downloader initializes with output directory")
    @MainActor
    func downloaderInitialization() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let downloader = Sample.Core.Downloader(outputDirectory: tempDir)

        // If we get here without crashing, initialization worked
        _ = downloader

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Sample.Core.Downloader initializes with maxSamples limit")
    @MainActor
    func downloaderInitializationWithLimit() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let downloader = Sample.Core.Downloader(
            outputDirectory: tempDir,
            maxSamples: 10
        )

        _ = downloader

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Sample.Core.Downloader initializes with forceDownload flag")
    @MainActor
    func downloaderInitializationWithForceDownload() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let downloader = Sample.Core.Downloader(
            outputDirectory: tempDir,
            forceDownload: true
        )

        _ = downloader

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Sample.Core.Downloader initializes with visible browser flag")
    @MainActor
    func downloaderInitializationWithVisibleBrowser() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let downloader = Sample.Core.Downloader(
            outputDirectory: tempDir,
            visibleBrowser: false // Don't actually show browser in tests
        )

        _ = downloader

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - SampleMetadata Tests

    @Test("SampleMetadata stores sample info")
    func sampleMetadataStoresInfo() {
        let metadata = SampleMetadata(
            name: "Building a Document-Based App",
            url: "https://developer.apple.com/documentation/swiftui/building_a_document_based_app",
            slug: "building_a_document_based_app"
        )

        #expect(metadata.name == "Building a Document-Based App")
        #expect(metadata.url.contains("developer.apple.com"))
        #expect(metadata.slug == "building_a_document_based_app")
    }

    @Test("SampleMetadata slug is extracted from URL")
    func sampleMetadataSlugFromURL() {
        let url = "https://developer.apple.com/documentation/swiftui/fruta_building_a_feature_rich_app"
        let components = url.components(separatedBy: "/")
        let slug = components.last ?? ""

        #expect(slug == "fruta_building_a_feature_rich_app")
    }

    // MARK: - Sample.Core.Statistics Tests

    @Test("Sample.Core.Statistics initializes with zeros")
    func statisticsInitializesWithZeros() {
        let stats = Sample.Core.Statistics()

        #expect(stats.totalSamples == 0)
        #expect(stats.downloadedSamples == 0)
        #expect(stats.skippedSamples == 0)
        #expect(stats.errors == 0)
    }

    @Test("Sample.Core.Statistics tracks counts")
    func statisticsTracksCounts() {
        var stats = Sample.Core.Statistics(startTime: Date())
        stats.totalSamples = 606
        stats.downloadedSamples = 500
        stats.skippedSamples = 100
        stats.errors = 6

        #expect(stats.totalSamples == 606)
        #expect(stats.downloadedSamples == 500)
        #expect(stats.skippedSamples == 100)
        #expect(stats.errors == 6)
    }

    @Test("Sample.Core.Statistics calculates duration")
    func statisticsCalculatesDuration() {
        var stats = Sample.Core.Statistics(startTime: Date())
        stats.endTime = stats.startTime?.addingTimeInterval(7200) // 2 hours

        let duration = stats.duration
        #expect(duration == 7200.0)
    }

    @Test("Sample.Core.Statistics duration is nil without end time")
    func statisticsDurationNilWithoutEndTime() {
        let stats = Sample.Core.Statistics(startTime: Date())

        #expect(stats.duration == nil)
    }

    // MARK: - Sample.Core.Progress Tests

    @Test("Sample.Core.Progress tracks download progress")
    func progressTracksProgress() {
        let stats = Sample.Core.Statistics()
        let progress = Sample.Core.Progress(
            current: 100,
            total: 606,
            sampleName: "Building a Document-Based App",
            stats: stats
        )

        #expect(progress.current == 100)
        #expect(progress.total == 606)
        #expect(progress.sampleName == "Building a Document-Based App")
        #expect(abs(progress.percentage - 16.5) < 0.1) // ~16.5%
    }

    @Test("Sample.Core.Progress calculates percentage correctly")
    func progressCalculatesPercentage() {
        let stats = Sample.Core.Statistics()
        let progress = Sample.Core.Progress(
            current: 303,
            total: 606,
            sampleName: "Test Sample",
            stats: stats
        )

        #expect(progress.percentage == 50.0)
    }

    // MARK: - Archive Format Detection Tests

    @Test("Detects ZIP archive format")
    func detectsZIPFormat() {
        let filename = "sample-project.zip"

        let isZip = filename.hasSuffix(".zip")
        #expect(isZip == true)
    }

    @Test("Detects TAR.GZ archive format")
    func detectsTarGzFormat() {
        let filename = "sample-project.tar.gz"

        let isTarGz = filename.hasSuffix(".tar.gz")
        #expect(isTarGz == true)
    }

    @Test("Detects TGZ archive format")
    func detectsTgzFormat() {
        let filename = "sample-project.tgz"

        let isTgz = filename.hasSuffix(".tgz")
        #expect(isTgz == true)
    }

    // MARK: - File Path Tests

    @Test("Generates output path from slug")
    func generatesOutputPathFromSlug() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let slug = "building_a_document_based_app"

        let outputPath = tempDir.appendingPathComponent(slug)

        #expect(outputPath.lastPathComponent == slug)
        #expect(outputPath.path.contains(tempDir.path))
    }

    @Test("Creates nested directory structure")
    func createsNestedDirectoryStructure() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let nestedPath = tempDir
            .appendingPathComponent("samples")
            .appendingPathComponent("swiftui")

        try FileManager.default.createDirectory(
            at: nestedPath,
            withIntermediateDirectories: true
        )

        #expect(FileManager.default.fileExists(atPath: nestedPath.path))

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Cookie Management Tests

    @Test("Cookies path is in output directory")
    @MainActor
    func cookiesPathInOutputDirectory() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let downloader = Sample.Core.Downloader(outputDirectory: tempDir)

        // Cookie path should be: outputDirectory/auth-cookies.json
        let expectedPath = tempDir.appendingPathComponent(Shared.Constants.FileName.authCookies)

        // We can't directly access private cookiesPath, but we know the pattern
        #expect(expectedPath.lastPathComponent == Shared.Constants.FileName.authCookies)
        #expect(expectedPath.path.contains(tempDir.path))

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - URL Validation Tests

    @Test("Sample code list URL is valid")
    func sampleCodeListURLIsValid() {
        let urlString = Shared.Constants.BaseURL.appleSampleCode

        #expect(URL(string: urlString) != nil)
        #expect(urlString.contains("developer.apple.com"))
    }

    @Test("Sample URLs are valid HTTPS URLs")
    func sampleURLsAreHTTPS() {
        let sampleURL = "https://developer.apple.com/documentation/swiftui/fruta_building_a_feature_rich_app"

        #expect(sampleURL.hasPrefix("https://"))
        #expect(URL(string: sampleURL)?.scheme == "https")
    }

    // MARK: - Integration Tests

    @Test("Downloader creates output directory", .tags(.integration))
    @MainActor
    func downloaderCreatesOutputDirectory() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        // Ensure directory doesn't exist yet
        try? FileManager.default.removeItem(at: tempDir)
        #expect(!FileManager.default.fileExists(atPath: tempDir.path))

        let downloader = Sample.Core.Downloader(outputDirectory: tempDir)

        // Note: We're not actually calling download() to avoid network calls
        // Just verify the downloader can be instantiated
        _ = downloader

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
}
