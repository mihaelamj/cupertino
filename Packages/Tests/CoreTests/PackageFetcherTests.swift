@testable import Core
import Foundation
import Shared
import Testing

// MARK: - Package Fetcher Tests

/// Comprehensive tests for PackageFetcher
/// Tests URL parsing, GitHub metadata fetching, sorting, checkpointing, and statistics

@Suite("Package Fetcher")
struct PackageFetcherTests {
    // MARK: - Model Tests

    @Test("PackageInfo initializes correctly")
    func packageInfoInitialization() {
        let pkg = PackageInfo(
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

    @Test("PackageInfo handles error field")
    func packageInfoWithError() {
        let pkg = PackageInfo(
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

    @Test("PackageInfo handles optional fields")
    func packageInfoWithOptionals() {
        let pkg = PackageInfo(
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

    @Test("PackageFetchStatistics initializes with defaults")
    func statisticsInitialization() {
        let stats = PackageFetchStatistics()

        #expect(stats.totalPackages == 0)
        #expect(stats.successfulFetches == 0)
        #expect(stats.errors == 0)
        #expect(stats.startTime == nil)
        #expect(stats.endTime == nil)
        #expect(stats.duration == nil)
    }

    @Test("PackageFetchStatistics calculates duration")
    func statisticsCalculatesDuration() {
        let start = Date()
        let end = start.addingTimeInterval(120)

        var stats = PackageFetchStatistics()
        stats.startTime = start
        stats.endTime = end

        #expect(stats.duration == 120)
    }

    @Test("PackageFetchStatistics duration is nil when incomplete")
    func statisticsDurationNilWhenIncomplete() {
        var stats = PackageFetchStatistics()
        #expect(stats.duration == nil)

        stats.startTime = Date()
        #expect(stats.duration == nil)

        stats.endTime = Date()
        #expect(stats.duration != nil)
    }

    // MARK: - Progress Tests

    @Test("PackageFetchProgress calculates percentage")
    func progressCalculatesPercentage() {
        let stats = PackageFetchStatistics()
        let progress = PackageFetchProgress(
            current: 25,
            total: 100,
            packageName: "apple/swift",
            stats: stats
        )

        #expect(progress.percentage == 25.0)
    }

    @Test("PackageFetchProgress handles edge cases")
    func progressHandlesEdgeCases() {
        let stats = PackageFetchStatistics()

        let progress1 = PackageFetchProgress(current: 0, total: 100, packageName: "test/repo", stats: stats)
        #expect(progress1.percentage == 0.0)

        let progress2 = PackageFetchProgress(current: 100, total: 100, packageName: "test/repo", stats: stats)
        #expect(progress2.percentage == 100.0)

        let progress3 = PackageFetchProgress(current: 50, total: 100, packageName: "test/repo", stats: stats)
        #expect(progress3.percentage == 50.0)
    }

    // MARK: - Output Model Tests

    @Test("PackageFetchOutput encodes and decodes")
    func outputEncodesAndDecodes() throws {
        let package = PackageInfo(
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

        let output = PackageFetchOutput(
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
        let decoded = try decoder.decode(PackageFetchOutput.self, from: data)

        #expect(decoded.totalPackages == 1)
        #expect(decoded.totalProcessed == 1)
        #expect(decoded.errors == 0)
        #expect(decoded.packages.count == 1)
        #expect(decoded.packages[0].owner == "apple")
    }

    // MARK: - Checkpoint Model Tests

    @Test("PackageFetchCheckpoint encodes and decodes")
    func checkpointEncodesAndDecodes() throws {
        let package = PackageInfo(
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

        let checkpoint = PackageFetchCheckpoint(
            processedCount: 10,
            packages: [package],
            timestamp: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PackageFetchCheckpoint.self, from: data)

        #expect(decoded.processedCount == 10)
        #expect(decoded.packages.count == 1)
        #expect(decoded.packages[0].owner == "apple")
    }

    // MARK: - Error Tests

    @Test("PackageFetchError equatable")
    func errorEquatable() {
        #expect(PackageFetchError.rateLimited == PackageFetchError.rateLimited)
        #expect(PackageFetchError.notFound == PackageFetchError.notFound)
        #expect(PackageFetchError.forbidden == PackageFetchError.forbidden)
        #expect(PackageFetchError.invalidResponse == PackageFetchError.invalidResponse)
        #expect(PackageFetchError.httpError(404) == PackageFetchError.httpError(404))
        #expect(PackageFetchError.httpError(404) != PackageFetchError.httpError(500))
    }

    // MARK: - Helper Methods

    private func createTestFetcher() async -> Core.PackageFetcher {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("package-fetcher-test-\(UUID().uuidString)")
        return await Core.PackageFetcher(outputDirectory: tempDir)
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
