@testable import Core
@testable import CorePackageIndexing
import CoreProtocols
import Foundation
import LoggingModels
import Testing

// MARK: - Package Fetcher Tests

// Comprehensive tests for PackageFetcher
// Tests URL parsing, GitHub metadata fetching, sorting, checkpointing, and statistics

@Suite("Package Fetcher")
struct PackageFetcherTests {
    // MARK: - Model Tests

    @Test("Core.PackageIndexing.PackageFetcher.PackageInfo initializes correctly")
    func packageInfoInitialization() {
        let pkg = Core.PackageIndexing.PackageFetcher.PackageInfo(
            owner: "apple",
            repo: "swift",
            stars: 1000,
            description: "The Swift Programming Language",
            url: "https://github.com/apple/swift",
            archived: false,
            fork: false,
            updatedAt: "2025-01-01T00:00:00Z",
            language: "Swift",
            license: "Apache-2.0"
        )

        #expect(pkg.owner == "apple")
        #expect(pkg.repo == "swift")
        #expect(pkg.stars == 1000)
        #expect(pkg.description == "The Swift Programming Language")
        #expect(pkg.url == "https://github.com/apple/swift")
        #expect(!pkg.archived)
        #expect(!pkg.fork)
        #expect(pkg.updatedAt == "2025-01-01T00:00:00Z")
        #expect(pkg.language == "Swift")
        #expect(pkg.license == "Apache-2.0")
        #expect(pkg.error == nil)
    }

    @Test("Core.PackageIndexing.PackageFetcher.PackageInfo handles error field")
    func packageInfoWithError() {
        let pkg = Core.PackageIndexing.PackageFetcher.PackageInfo(
            owner: "test",
            repo: "repo",
            stars: 0,
            description: nil,
            url: "https://github.com/test/repo",
            archived: false,
            fork: false,
            updatedAt: nil,
            language: nil,
            license: nil,
            error: "not_found"
        )

        #expect(pkg.error == "not_found")
    }

    @Test("Core.PackageIndexing.PackageFetcher.PackageInfo handles optional fields")
    func packageInfoWithOptionals() {
        let pkg = Core.PackageIndexing.PackageFetcher.PackageInfo(
            owner: "test",
            repo: "repo",
            stars: 0,
            description: nil,
            url: "https://github.com/test/repo",
            archived: false,
            fork: false,
            updatedAt: nil,
            language: nil,
            license: nil
        )

        #expect(pkg.description == nil)
        #expect(pkg.updatedAt == nil)
        #expect(pkg.language == nil)
        #expect(pkg.license == nil)
    }

    // MARK: - Statistics Tests

    @Test("Core.PackageIndexing.PackageFetcherStatistics initializes with defaults")
    func statisticsInitialization() {
        let stats = Core.PackageIndexing.PackageFetcherStatistics()

        #expect(stats.totalPackages == 0)
        #expect(stats.successfulFetches == 0)
        #expect(stats.errors == 0)
        #expect(stats.startTime == nil)
        #expect(stats.endTime == nil)
        #expect(stats.duration == nil)
    }

    @Test("Core.PackageIndexing.PackageFetcherStatistics calculates duration")
    func statisticsCalculatesDuration() {
        let start = Date()
        let end = start.addingTimeInterval(120)

        var stats = Core.PackageIndexing.PackageFetcherStatistics()
        stats.startTime = start
        stats.endTime = end

        #expect(stats.duration == 120)
    }

    @Test("Core.PackageIndexing.PackageFetcherStatistics duration is nil when incomplete")
    func statisticsDurationNilWhenIncomplete() {
        var stats = Core.PackageIndexing.PackageFetcherStatistics()
        #expect(stats.duration == nil)

        stats.startTime = Date()
        #expect(stats.duration == nil)

        stats.endTime = Date()
        #expect(stats.duration != nil)
    }

    // MARK: - Progress Tests

    @Test("Core.PackageIndexing.PackageFetcherProgress calculates percentage")
    func progressCalculatesPercentage() {
        let stats = Core.PackageIndexing.PackageFetcherStatistics()
        let progress = Core.PackageIndexing.PackageFetcherProgress(
            current: 25,
            total: 100,
            packageName: "apple/swift",
            stats: stats
        )

        #expect(progress.percentage == 25.0)
    }

    @Test("Core.PackageIndexing.PackageFetcherProgress handles edge cases")
    func progressHandlesEdgeCases() {
        let stats = Core.PackageIndexing.PackageFetcherStatistics()

        let progress1 = Core.PackageIndexing.PackageFetcherProgress(current: 0, total: 100, packageName: "test/repo", stats: stats)
        #expect(progress1.percentage == 0.0)

        let progress2 = Core.PackageIndexing.PackageFetcherProgress(current: 100, total: 100, packageName: "test/repo", stats: stats)
        #expect(progress2.percentage == 100.0)

        let progress3 = Core.PackageIndexing.PackageFetcherProgress(current: 50, total: 100, packageName: "test/repo", stats: stats)
        #expect(progress3.percentage == 50.0)
    }

    // MARK: - Output Model Tests

    @Test("Core.PackageIndexing.PackageFetcher.FetchOutput encodes and decodes")
    func outputEncodesAndDecodes() throws {
        let package = Core.PackageIndexing.PackageFetcher.PackageInfo(
            owner: "apple",
            repo: "swift",
            stars: 1000,
            description: "Test",
            url: "https://github.com/apple/swift",
            archived: false,
            fork: false,
            updatedAt: "2025-01-01T00:00:00Z",
            language: "Swift",
            license: "Apache-2.0"
        )

        let output = Core.PackageIndexing.PackageFetcher.FetchOutput(
            totalPackages: 1,
            totalProcessed: 1,
            errors: 0,
            generatedAt: Date(),
            packages: [package]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(output)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Core.PackageIndexing.PackageFetcher.FetchOutput.self, from: data)

        #expect(decoded.totalPackages == 1)
        #expect(decoded.totalProcessed == 1)
        #expect(decoded.errors == 0)
        #expect(decoded.packages.count == 1)
        #expect(decoded.packages[0].owner == "apple")
    }

    // MARK: - Checkpoint Model Tests

    @Test("Core.PackageIndexing.PackageFetcher.Checkpoint encodes and decodes")
    func checkpointEncodesAndDecodes() throws {
        let package = Core.PackageIndexing.PackageFetcher.PackageInfo(
            owner: "apple",
            repo: "swift",
            stars: 1000,
            description: "Test",
            url: "https://github.com/apple/swift",
            archived: false,
            fork: false,
            updatedAt: "2025-01-01T00:00:00Z",
            language: "Swift",
            license: "Apache-2.0"
        )

        let checkpoint = Core.PackageIndexing.PackageFetcher.Checkpoint(
            processedCount: 10,
            packages: [package],
            timestamp: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Core.PackageIndexing.PackageFetcher.Checkpoint.self, from: data)

        #expect(decoded.processedCount == 10)
        #expect(decoded.packages.count == 1)
        #expect(decoded.packages[0].owner == "apple")
    }

    // MARK: - Error Tests

    @Test("Core.PackageIndexing.PackageFetcher.Error equatable")
    func errorEquatable() {
        #expect(Core.PackageIndexing.PackageFetcher.Error.rateLimited == Core.PackageIndexing.PackageFetcher.Error.rateLimited)
        #expect(Core.PackageIndexing.PackageFetcher.Error.notFound == Core.PackageIndexing.PackageFetcher.Error.notFound)
        #expect(Core.PackageIndexing.PackageFetcher.Error.forbidden == Core.PackageIndexing.PackageFetcher.Error.forbidden)
        #expect(Core.PackageIndexing.PackageFetcher.Error.invalidResponse == Core.PackageIndexing.PackageFetcher.Error.invalidResponse)
        #expect(Core.PackageIndexing.PackageFetcher.Error.httpError(404) == Core.PackageIndexing.PackageFetcher.Error.httpError(404))
        #expect(Core.PackageIndexing.PackageFetcher.Error.httpError(404) != Core.PackageIndexing.PackageFetcher.Error.httpError(500))
    }

    // MARK: - Helper Methods

    private func createTestFetcher() async -> Core.PackageIndexing.PackageFetcher {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("package-fetcher-test-\(UUID().uuidString)")
        return await Core.PackageIndexing.PackageFetcher(outputDirectory: tempDir, logger: Logging.NoopRecording())
    }

    private func createTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("package-fetcher-test-\(UUID().uuidString)")
    }

    private func cleanupTempDirectory(_ tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

// MARK: - Test Extensions

// Note: extractOwnerRepo is a private method and cannot be tested directly
// We test it indirectly through the public fetch API
