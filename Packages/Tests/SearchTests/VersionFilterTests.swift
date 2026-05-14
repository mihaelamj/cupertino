import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

// MARK: - Release.Version Filter Tests

@Suite("Release.Version Filter Tests", .serialized)
struct VersionFilterTests {
    // MARK: - Basic Release.Version Comparison

    @Test("Equal versions match")
    func equalVersions() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios15",
            title: "iOS 15 API",
            minIOS: "15.0"
        )
        defer { cleanup() }

        let results = try await index.search(query: "iOS", minIOS: "15.0")
        #expect(results.count == 1)
        #expect(results.first?.title == "iOS 15 API")
    }

    @Test("Older API matches newer target")
    func olderAPIMatchesNewerTarget() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios13",
            title: "iOS 13 API",
            minIOS: "13.0"
        )
        defer { cleanup() }

        // API from iOS 13 should match when targeting iOS 15
        let results = try await index.search(query: "iOS", minIOS: "15.0")
        #expect(results.count == 1)
    }

    @Test("Newer API excluded from older target")
    func newerAPIExcludedFromOlderTarget() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios18",
            title: "iOS 18 API",
            minIOS: "18.0"
        )
        defer { cleanup() }

        // API from iOS 18 should NOT match when targeting iOS 15
        let results = try await index.search(query: "iOS", minIOS: "15.0")
        #expect(results.isEmpty)
    }

    // MARK: - Semantic Release.Version Comparison (Critical)

    @Test("10.13 vs 10.2: semantic comparison handles double-digit minor")
    func semanticVersionDoubleDigitMinor() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://macos1013",
            title: "macOS 10.13 API",
            minMacOS: "10.13"
        )
        defer { cleanup() }

        // 10.13 > 10.2 semantically (13 > 2), should NOT match 10.2 target
        let resultsOld = try await index.search(query: "macOS", minMacOS: "10.2")
        #expect(resultsOld.isEmpty, "10.13 API should not match 10.2 target")

        // Should match 10.13 exactly
        let resultsExact = try await index.search(query: "macOS", minMacOS: "10.13")
        #expect(resultsExact.count == 1)

        // Should match 10.14 (newer)
        let resultsNewer = try await index.search(query: "macOS", minMacOS: "10.14")
        #expect(resultsNewer.count == 1)
    }

    @Test("Three-component version: 12.1.1")
    func threeComponentVersion() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios1211",
            title: "iOS 12.1.1 API",
            minIOS: "12.1.1"
        )
        defer { cleanup() }

        // 12.1.1 > 12.1.0, should NOT match 12.1
        let results121 = try await index.search(query: "iOS", minIOS: "12.1")
        #expect(results121.isEmpty, "12.1.1 API should not match 12.1 target")

        // Should match 12.1.1 exactly
        let results1211 = try await index.search(query: "iOS", minIOS: "12.1.1")
        #expect(results1211.count == 1)

        // Should match 12.2.0
        let results122 = try await index.search(query: "iOS", minIOS: "12.2")
        #expect(results122.count == 1)
    }

    @Test("Single digit version")
    func singleDigitVersion() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios11",
            title: "iOS 11 API",
            minIOS: "11"
        )
        defer { cleanup() }

        // iOS 11 == iOS 11.0, should match 11.0
        let results = try await index.search(query: "iOS", minIOS: "11.0")
        #expect(results.count == 1)
    }

    // MARK: - Platform-Specific Filters (Parameterized)

    struct PlatformTestCase {
        let name: String
        let platform: Platform
        let apiVersion: String
        let excludedTarget: String
        let matchingTarget: String

        enum Platform {
            case iOS, macOS, tvOS, watchOS, visionOS
        }
    }

    static let platformTestCases: [PlatformTestCase] = [
        PlatformTestCase(
            name: "iOS",
            platform: .iOS,
            apiVersion: "16.0",
            excludedTarget: "15.0",
            matchingTarget: "16.0"
        ),
        PlatformTestCase(
            name: "macOS",
            platform: .macOS,
            apiVersion: "13.0",
            excludedTarget: "12.0",
            matchingTarget: "13.0"
        ),
        PlatformTestCase(
            name: "tvOS",
            platform: .tvOS,
            apiVersion: "16.0",
            excludedTarget: "15.0",
            matchingTarget: "16.0"
        ),
        PlatformTestCase(
            name: "watchOS",
            platform: .watchOS,
            apiVersion: "9.0",
            excludedTarget: "8.0",
            matchingTarget: "9.0"
        ),
        PlatformTestCase(
            name: "visionOS",
            platform: .visionOS,
            apiVersion: "2.0",
            excludedTarget: "1.0",
            matchingTarget: "2.0"
        ),
    ]

    @Test("Platform version filter", arguments: platformTestCases)
    func platformFilter(testCase: PlatformTestCase) async throws {
        let (index, cleanup) = try await Self.createVersionedDocForPlatform(
            platform: testCase.platform,
            version: testCase.apiVersion,
            title: "\(testCase.name) \(testCase.apiVersion) API"
        )
        defer { cleanup() }

        // Should NOT match when target is older than API
        let excludedResults = try await Self.searchWithPlatform(
            index: index,
            query: testCase.name,
            platform: testCase.platform,
            version: testCase.excludedTarget
        )
        #expect(
            excludedResults.isEmpty,
            "\(testCase.name) \(testCase.apiVersion) should not match \(testCase.excludedTarget)"
        )

        // Should match when target equals API version
        let matchingResults = try await Self.searchWithPlatform(
            index: index,
            query: testCase.name,
            platform: testCase.platform,
            version: testCase.matchingTarget
        )
        #expect(matchingResults.count == 1)
    }

    // MARK: - Multiple Platform Filters

    @Test("Multiple platforms: all must match")
    func multiplePlatformFilters() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://multiplatform",
            title: "Multi-platform API",
            minIOS: "15.0",
            minMacOS: "12.0",
            minTvOS: "15.0",
            minWatchOS: "8.0",
            minVisionOS: "1.0"
        )
        defer { cleanup() }

        // Should match when both iOS and macOS satisfied
        let resultsAll = try await index.search(
            query: "Multi",
            minIOS: "16.0",
            minMacOS: "13.0"
        )
        #expect(resultsAll.count == 1)

        // Should NOT match if iOS target is too old
        let resultsFailIOS = try await index.search(
            query: "Multi",
            minIOS: "14.0" // iOS 15 API, targeting 14
        )
        #expect(resultsFailIOS.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("No availability data: excluded when filtered")
    func noAvailabilityData() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording())
        defer {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: tempDB)
        }

        // Index document WITHOUT availability data
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: "test://noavail",
            source: "apple-docs",
            framework: "test",
            title: "No Availability API",
            content: "Content without availability",
            filePath: "/test.md",
            contentHash: "hash",
            lastCrawled: Date(),
            sourceType: "test"
        ))

        // Without availability, should not appear in filtered results
        let filtered = try await index.search(query: "Availability", minIOS: "15.0")
        #expect(filtered.isEmpty)

        // But should appear in unfiltered results
        let unfiltered = try await index.search(query: "Availability")
        #expect(unfiltered.count == 1)
    }

    @Test("Filter with no matching results returns empty")
    func filterNoMatches() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://old",
            title: "Old API",
            minIOS: "18.0"
        )
        defer { cleanup() }

        let results = try await index.search(query: "Old", minIOS: "8.0")
        #expect(results.isEmpty)
    }

    // MARK: - Malformed Release.Version Edge Cases

    @Test("Empty version string treated as no filter")
    func emptyVersionString() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios15",
            title: "iOS 15 API",
            minIOS: "15.0"
        )
        defer { cleanup() }

        // Empty string should be treated as no filter (implementation dependent)
        // Document should appear since no valid filter applied
        let results = try await index.search(query: "iOS", minIOS: "")
        #expect(results.count == 1, "Empty version should not filter")
    }

    @Test("Non-numeric version components handled gracefully")
    func nonNumericVersion() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios15",
            title: "iOS 15 API",
            minIOS: "15.0"
        )
        defer { cleanup() }

        // Non-numeric version should be handled gracefully (not crash)
        // Behavior: invalid versions parse to empty components, comparison treats as 0
        let results = try await index.search(query: "iOS", minIOS: "abc")
        // With "abc" parsing to [0], and API at 15.0, API > target, so excluded
        #expect(results.isEmpty, "Invalid version 'abc' parses as 0, excluding iOS 15 API")
    }

    @Test("Release.Version with many components")
    func manyComponentVersion() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios15",
            title: "iOS 15.0.1.2 API",
            minIOS: "15.0.1.2"
        )
        defer { cleanup() }

        // Should handle 4+ component versions
        let resultsExact = try await index.search(query: "iOS", minIOS: "15.0.1.2")
        #expect(resultsExact.count == 1)

        let resultsNewer = try await index.search(query: "iOS", minIOS: "15.0.1.3")
        #expect(resultsNewer.count == 1)

        let resultsOlder = try await index.search(query: "iOS", minIOS: "15.0.1.1")
        #expect(resultsOlder.isEmpty)
    }

    @Test("Leading zeros in version")
    func leadingZerosVersion() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://ios15",
            title: "iOS 15 API",
            minIOS: "15.0"
        )
        defer { cleanup() }

        // "015.000" should parse same as "15.0"
        let results = try await index.search(query: "iOS", minIOS: "015.000")
        #expect(results.count == 1, "Leading zeros should be handled")
    }

    @Test("Very large version numbers")
    func largeVersionNumbers() async throws {
        let (index, cleanup) = try await Self.createVersionedDoc(
            uri: "test://future",
            title: "Future API",
            minIOS: "999.999.999"
        )
        defer { cleanup() }

        // Large version should work
        let resultsExact = try await index.search(query: "Future", minIOS: "999.999.999")
        #expect(resultsExact.count == 1)

        let resultsOlder = try await index.search(query: "Future", minIOS: "100.0")
        #expect(resultsOlder.isEmpty)
    }

    // MARK: - Helpers

    private static func createVersionedDoc(
        uri: String,
        title: String,
        minIOS: String? = nil,
        minMacOS: String? = nil,
        minTvOS: String? = nil,
        minWatchOS: String? = nil,
        minVisionOS: String? = nil
    ) async throws -> (index: Search.Index, cleanup: @Sendable () -> Void) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording())

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: uri,
            source: "apple-docs",
            framework: "test",
            title: title,
            content: "\(title) content for testing",
            filePath: "/test.md",
            contentHash: "hash-\(uri)",
            lastCrawled: Date(),
            sourceType: "test",
            minIOS: minIOS,
            minMacOS: minMacOS,
            minTvOS: minTvOS,
            minWatchOS: minWatchOS,
            minVisionOS: minVisionOS
        ))

        let cleanup: @Sendable () -> Void = {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: tempDB)
        }

        return (index, cleanup)
    }

    private static func createVersionedDocForPlatform(
        platform: PlatformTestCase.Platform,
        version: String,
        title: String
    ) async throws -> (index: Search.Index, cleanup: @Sendable () -> Void) {
        switch platform {
        case .iOS:
            return try await createVersionedDoc(uri: "test://\(platform)-\(version)", title: title, minIOS: version)
        case .macOS:
            return try await createVersionedDoc(uri: "test://\(platform)-\(version)", title: title, minMacOS: version)
        case .tvOS:
            return try await createVersionedDoc(uri: "test://\(platform)-\(version)", title: title, minTvOS: version)
        case .watchOS:
            return try await createVersionedDoc(uri: "test://\(platform)-\(version)", title: title, minWatchOS: version)
        case .visionOS:
            return try await createVersionedDoc(uri: "test://\(platform)-\(version)", title: title, minVisionOS: version)
        }
    }

    private static func searchWithPlatform(
        index: Search.Index,
        query: String,
        platform: PlatformTestCase.Platform,
        version: String
    ) async throws -> [Search.Result] {
        switch platform {
        case .iOS:
            return try await index.search(query: query, minIOS: version)
        case .macOS:
            return try await index.search(query: query, minMacOS: version)
        case .tvOS:
            return try await index.search(query: query, minTvOS: version)
        case .watchOS:
            return try await index.search(query: query, minWatchOS: version)
        case .visionOS:
            return try await index.search(query: query, minVisionOS: version)
        }
    }
}
