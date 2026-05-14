@testable import Availability
import Foundation
import Testing

// MARK: - Platform Availability Tests

@Suite("Availability.Platform Tests")
struct PlatformAvailabilityTests {
    @Test("Initialize with all parameters")
    func fullInitialization() {
        let availability = Availability.Platform(
            name: "iOS",
            introducedAt: "13.0",
            deprecated: true,
            deprecatedAt: "17.0",
            unavailable: false,
            beta: false
        )

        #expect(availability.name == "iOS")
        #expect(availability.introducedAt == "13.0")
        #expect(availability.deprecated == true)
        #expect(availability.deprecatedAt == "17.0")
        #expect(availability.unavailable == false)
        #expect(availability.beta == false)
    }

    @Test("Initialize with minimal parameters")
    func minimalInitialization() {
        let availability = Availability.Platform(name: "macOS")

        #expect(availability.name == "macOS")
        #expect(availability.introducedAt == nil)
        #expect(availability.deprecated == false)
        #expect(availability.deprecatedAt == nil)
        #expect(availability.unavailable == false)
        #expect(availability.beta == false)
    }

    @Test("Hashable conformance")
    func hashable() {
        let iosAvailability = Availability.Platform(name: "iOS", introducedAt: "13.0")
        let iosAvailabilityCopy = Availability.Platform(name: "iOS", introducedAt: "13.0")
        let macOSAvailability = Availability.Platform(name: "macOS", introducedAt: "10.15")

        #expect(iosAvailability == iosAvailabilityCopy)
        #expect(iosAvailability != macOSAvailability)
        #expect(iosAvailability.hashValue == iosAvailabilityCopy.hashValue)
    }

    @Test("Codable round-trip")
    func codable() throws {
        let original = Availability.Platform(
            name: "iOS",
            introducedAt: "15.0",
            deprecated: false,
            deprecatedAt: nil,
            unavailable: false,
            beta: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Availability.Platform.self, from: data)

        #expect(decoded == original)
    }
}

// MARK: - Availability Info Tests

@Suite("Availability.Info Tests")
struct AvailabilityInfoTests {
    @Test("Empty availability")
    func testEmpty() {
        let empty = Availability.Info.empty

        #expect(empty.isEmpty == true)
        #expect(empty.platforms.isEmpty == true)
        #expect(empty.minimumiOS == nil)
        #expect(empty.minimumMacOS == nil)
        #expect(empty.isDeprecated == false)
        #expect(empty.isBeta == false)
    }

    @Test("Non-empty availability")
    func nonEmpty() {
        let platforms = [
            Availability.Platform(name: "iOS", introducedAt: "13.0"),
            Availability.Platform(name: "macOS", introducedAt: "10.15"),
        ]
        let info = Availability.Info(platforms: platforms)

        #expect(info.isEmpty == false)
        #expect(info.platforms.count == 2)
    }

    @Test("Minimum iOS version")
    func testMinimumiOS() {
        let platforms = [
            Availability.Platform(name: "iOS", introducedAt: "14.0"),
            Availability.Platform(name: "macOS", introducedAt: "11.0"),
        ]
        let info = Availability.Info(platforms: platforms)

        #expect(info.minimumiOS == "14.0")
    }

    @Test("Minimum macOS version")
    func testMinimumMacOS() {
        let platforms = [
            Availability.Platform(name: "iOS", introducedAt: "15.0"),
            Availability.Platform(name: "macOS", introducedAt: "12.0"),
        ]
        let info = Availability.Info(platforms: platforms)

        #expect(info.minimumMacOS == "12.0")
    }

    @Test("iOS unavailable returns nil")
    func unavailableiOS() {
        let platforms = [
            Availability.Platform(name: "iOS", introducedAt: "13.0", unavailable: true),
            Availability.Platform(name: "macOS", introducedAt: "10.15"),
        ]
        let info = Availability.Info(platforms: platforms)

        #expect(info.minimumiOS == nil)
        #expect(info.minimumMacOS == "10.15")
    }

    @Test("Deprecation check - deprecated")
    func isDeprecatedTrue() {
        let platforms = [
            Availability.Platform(name: "iOS", introducedAt: "10.0", deprecated: true),
            Availability.Platform(name: "macOS", introducedAt: "10.12"),
        ]
        let info = Availability.Info(platforms: platforms)

        #expect(info.isDeprecated == true)
    }

    @Test("Deprecation check - not deprecated")
    func isDeprecatedFalse() {
        let platforms = [
            Availability.Platform(name: "iOS", introducedAt: "15.0"),
            Availability.Platform(name: "macOS", introducedAt: "12.0"),
        ]
        let info = Availability.Info(platforms: platforms)

        #expect(info.isDeprecated == false)
    }

    @Test("Beta check - in beta")
    func isBetaTrue() {
        let platforms = [
            Availability.Platform(name: "visionOS", introducedAt: "1.0", beta: true),
        ]
        let info = Availability.Info(platforms: platforms)

        #expect(info.isBeta == true)
    }

    @Test("Beta check - not in beta")
    func isBetaFalse() {
        let platforms = [
            Availability.Platform(name: "iOS", introducedAt: "17.0"),
        ]
        let info = Availability.Info(platforms: platforms)

        #expect(info.isBeta == false)
    }

    @Test("Codable round-trip")
    func testCodable() throws {
        let platforms = [
            Availability.Platform(name: "iOS", introducedAt: "16.0"),
            Availability.Platform(name: "watchOS", introducedAt: "9.0"),
        ]
        let original = Availability.Info(platforms: platforms)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Availability.Info.self, from: data)

        #expect(decoded.platforms.count == original.platforms.count)
        #expect(decoded.minimumiOS == original.minimumiOS)
    }
}

// MARK: - Availability Statistics Tests

@Suite("Availability.Statistics Tests")
struct AvailabilityStatisticsTests {
    @Test("Default initialization")
    func defaultInit() {
        let stats = Availability.Statistics()

        #expect(stats.totalDocuments == 0)
        #expect(stats.updatedDocuments == 0)
        #expect(stats.successfulFetches == 0)
        #expect(stats.failedFetches == 0)
        #expect(stats.skippedDocuments == 0)
        #expect(stats.frameworksProcessed == 0)
        #expect(stats.startTime == nil)
        #expect(stats.endTime == nil)
        #expect(stats.duration == nil)
    }

    @Test("Duration calculation")
    func testDuration() {
        let start = Date()
        let end = start.addingTimeInterval(120)

        let stats = Availability.Statistics(
            startTime: start,
            endTime: end
        )

        #expect(stats.duration == 120)
    }

    @Test("Duration nil when no end time")
    func durationNilNoEnd() {
        let stats = Availability.Statistics(startTime: Date())

        #expect(stats.duration == nil)
    }

    @Test("Duration nil when no start time")
    func durationNilNoStart() {
        let stats = Availability.Statistics(endTime: Date())

        #expect(stats.duration == nil)
    }

    @Test("Success rate calculation - all successful")
    func successRateAllSuccess() {
        var stats = Availability.Statistics()
        stats.successfulFetches = 100
        stats.failedFetches = 0

        #expect(stats.successRate == 100.0)
    }

    @Test("Success rate calculation - mixed")
    func successRateMixed() {
        var stats = Availability.Statistics()
        stats.successfulFetches = 75
        stats.failedFetches = 25

        #expect(stats.successRate == 75.0)
    }

    @Test("Success rate calculation - all failed")
    func successRateAllFailed() {
        var stats = Availability.Statistics()
        stats.successfulFetches = 0
        stats.failedFetches = 50

        #expect(stats.successRate == 0.0)
    }

    @Test("Success rate calculation - no attempts")
    func successRateNoAttempts() {
        let stats = Availability.Statistics()

        #expect(stats.successRate == 0.0)
    }
}

// MARK: - Availability Progress Tests

@Suite("Availability.Progress Tests")
struct AvailabilityProgressTests {
    @Test("Progress percentage calculation")
    func testPercentage() {
        let progress = Availability.Progress(
            currentDocument: "test.json",
            completed: 50,
            total: 100,
            successful: 45,
            failed: 5,
            currentFramework: "SwiftUI"
        )

        #expect(progress.percentage == 50.0)
    }

    @Test("Progress percentage - zero total")
    func percentageZeroTotal() {
        let progress = Availability.Progress(
            currentDocument: "test.json",
            completed: 0,
            total: 0,
            successful: 0,
            failed: 0,
            currentFramework: "SwiftUI"
        )

        #expect(progress.percentage == 0.0)
    }

    @Test("Progress percentage - 100%")
    func percentageFull() {
        let progress = Availability.Progress(
            currentDocument: "last.json",
            completed: 200,
            total: 200,
            successful: 190,
            failed: 10,
            currentFramework: "Foundation"
        )

        #expect(progress.percentage == 100.0)
    }

    @Test("Progress stores all values")
    func allValues() {
        let progress = Availability.Progress(
            currentDocument: "view.json",
            completed: 10,
            total: 50,
            successful: 8,
            failed: 2,
            currentFramework: "UIKit"
        )

        #expect(progress.currentDocument == "view.json")
        #expect(progress.completed == 10)
        #expect(progress.total == 50)
        #expect(progress.successful == 8)
        #expect(progress.failed == 2)
        #expect(progress.currentFramework == "UIKit")
    }
}

// MARK: - Availability Error Tests

@Suite("Availability.Error Tests")
struct AvailabilityErrorTests {
    @Test("Network error description")
    func testNetworkError() {
        let userInfo = [NSLocalizedDescriptionKey: "Connection failed"]
        let underlyingError = NSError(domain: "test", code: -1, userInfo: userInfo)
        let error = Availability.Error.networkError(underlyingError)

        #expect(error.errorDescription?.contains("Network error") == true)
        #expect(error.errorDescription?.contains("Connection failed") == true)
    }

    @Test("Timeout error description")
    func timeoutError() {
        let error = Availability.Error.timeout

        #expect(error.errorDescription == "Request timed out")
    }

    @Test("Not found error description")
    func notFoundError() {
        let error = Availability.Error.notFound("SwiftUI/View")

        #expect(error.errorDescription?.contains("not found") == true)
        #expect(error.errorDescription?.contains("SwiftUI/View") == true)
    }

    @Test("Invalid response error description")
    func invalidResponseError() {
        let error = Availability.Error.invalidResponse

        #expect(error.errorDescription == "Invalid response from Apple API")
    }

    @Test("Rate limited error description")
    func rateLimitedError() {
        let error = Availability.Error.rateLimited

        #expect(error.errorDescription == "Rate limited by Apple API")
    }

    @Test("No documentation found error description")
    func noDocumentationFoundError() {
        let error = Availability.Error.noDocumentationFound

        #expect(error.errorDescription == "No documentation directory found")
    }

    @Test("JSON parse error description")
    func jSONParseError() {
        let underlyingError = NSError(domain: "JSON", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        let error = Availability.Error.jsonParseError(underlyingError)

        #expect(error.errorDescription?.contains("JSON parse error") == true)
    }

    @Test("Write error description")
    func testWriteError() {
        let userInfo = [NSLocalizedDescriptionKey: "Permission denied"]
        let underlyingError = NSError(domain: "File", code: 2, userInfo: userInfo)
        let error = Availability.Error.writeError(underlyingError)

        #expect(error.errorDescription?.contains("Failed to write file") == true)
    }
}

// MARK: - Availability Fetcher Configuration Tests

@Suite("Availability.Fetcher.Configuration Tests")
struct AvailabilityFetcherConfigurationTests {
    @Test("Default configuration values")
    func defaultConfig() {
        let config = Availability.Fetcher.Configuration.default

        #expect(config.concurrency == 50)
        #expect(config.timeout == 1.0)
        #expect(config.skipExisting == false)
        #expect(config.apiBaseURL == "https://developer.apple.com/tutorials/data/documentation")
    }

    @Test("Fast configuration values")
    func fastConfig() {
        let config = Availability.Fetcher.Configuration.fast

        #expect(config.concurrency == 100)
        #expect(config.timeout == 0.5)
        #expect(config.skipExisting == true)
    }

    @Test("Custom configuration")
    func customConfig() {
        let config = Availability.Fetcher.Configuration(
            concurrency: 25,
            timeout: 2.0,
            skipExisting: true,
            apiBaseURL: "https://custom.api.com"
        )

        #expect(config.concurrency == 25)
        #expect(config.timeout == 2.0)
        #expect(config.skipExisting == true)
        #expect(config.apiBaseURL == "https://custom.api.com")
    }
}

// MARK: - @available Annotation Parser Tests

@Suite("Availability.Info Annotation Parser Tests")
struct AvailabilityAnnotationParserTests {
    @Test("Parse simple @available annotation")
    func parseSimpleAnnotation() {
        let code = "@available(iOS 13.0, macOS 10.15, *)"
        let result = Availability.Info.parseFromAnnotation(code)

        #expect(result != nil)
        #expect(result?.platforms.count == 2)
        #expect(result?.minimumiOS == "13.0")
        #expect(result?.minimumMacOS == "10.15")
    }

    @Test("Parse multiple platforms")
    func parseMultiplePlatforms() {
        let code = "@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)"
        let result = Availability.Info.parseFromAnnotation(code)

        #expect(result != nil)
        #expect(result?.platforms.count == 5)
        #expect(result?.minimumiOS == "18.0")
        #expect(result?.minimumMacOS == "15.0")
    }

    @Test("Parse annotation with extra whitespace")
    func parseWithWhitespace() {
        let code = "@available(  iOS 16.0 ,  macOS 13.0  , * )"
        let result = Availability.Info.parseFromAnnotation(code)

        #expect(result != nil)
        #expect(result?.minimumiOS == "16.0")
        #expect(result?.minimumMacOS == "13.0")
    }

    @Test("Parse annotation in code block")
    func parseInCodeBlock() {
        let code = """
        import SwiftUI

        @available(iOS 17.0, macOS 14.0, *)
        struct MyView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        let result = Availability.Info.parseFromAnnotation(code)

        #expect(result != nil)
        #expect(result?.minimumiOS == "17.0")
        #expect(result?.minimumMacOS == "14.0")
    }

    @Test("No annotation returns nil")
    func noAnnotation() {
        let code = "struct MyView: View { }"
        let result = Availability.Info.parseFromAnnotation(code)

        #expect(result == nil)
    }

    @Test("Platform name normalization")
    func platformNormalization() {
        let code = "@available(ios 15.0, MACOS 12.0, watchos 8.0, *)"
        let result = Availability.Info.parseFromAnnotation(code)

        #expect(result != nil)
        // Check normalized names
        let platformNames = result?.platforms.map(\.name) ?? []
        #expect(platformNames.contains("iOS"))
        #expect(platformNames.contains("macOS"))
        #expect(platformNames.contains("watchOS"))
    }

    @Test("Extract from JSON rawMarkdown")
    func extractFromJSON() throws {
        let json: [String: Any] = [
            "title": "Test",
            "rawMarkdown": """
            # Test
            ```swift
            @available(iOS 16.0, macOS 13.0, *)
            func test() { }
            ```
            """,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = Availability.Info.extractFromJSONContent(data)

        #expect(result != nil)
        #expect(result?.minimumiOS == "16.0")
    }

    @Test("Extract from JSON declaration")
    func extractFromDeclaration() throws {
        let json: [String: Any] = [
            "title": "Test",
            "declaration": [
                "code": "@available(iOS 15.0, *)\nfunc test() { }",
                "language": "swift",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = Availability.Info.extractFromJSONContent(data)

        #expect(result != nil)
        #expect(result?.minimumiOS == "15.0")
    }

    @Test("Extract from JSON code examples")
    func extractFromCodeExamples() throws {
        let json: [String: Any] = [
            "title": "Test",
            "codeExamples": [
                ["code": "@available(iOS 17.0, macOS 14.0, *)\nstruct Example { }"],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = Availability.Info.extractFromJSONContent(data)

        #expect(result != nil)
        #expect(result?.minimumiOS == "17.0")
        #expect(result?.minimumMacOS == "14.0")
    }
}

// MARK: - Availability.Fetcher.buildAPIURL Tests

@Suite("Availability.Fetcher.buildAPIURL Tests")
struct FetcherBuildAPIURLTests {
    private let defaultFetcher = Availability.Fetcher(
        docsDirectory: URL(fileURLWithPath: "/tmp")
    )

    @Test("strips /documentation/ prefix, lowercases path, and appends .json")
    func stripsDocumentationPrefix() async throws {
        let docURL = try #require(URL(string: "https://developer.apple.com/documentation/SwiftUI/View"))
        let result = await defaultFetcher.buildAPIURL(from: docURL)
        #expect(result.absoluteString == "https://developer.apple.com/tutorials/data/documentation/swiftui/view.json")
    }

    @Test("handles mixed-case framework and symbol names")
    func mixedCasePath() async throws {
        let docURL = try #require(URL(string: "https://developer.apple.com/documentation/Foundation/URL"))
        let result = await defaultFetcher.buildAPIURL(from: docURL)
        #expect(result.absoluteString == "https://developer.apple.com/tutorials/data/documentation/foundation/url.json")
    }

    @Test("custom apiBaseURL is used in constructed URL")
    func customBaseURL() async throws {
        let config = Availability.Fetcher.Configuration(
            apiBaseURL: "https://custom.example.com/data/documentation"
        )
        let fetcher = Availability.Fetcher(
            docsDirectory: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        let docURL = try #require(URL(string: "https://developer.apple.com/documentation/Combine/Publisher"))
        let result = await fetcher.buildAPIURL(from: docURL)
        #expect(result.absoluteString == "https://custom.example.com/data/documentation/combine/publisher.json")
    }

    @Test("always produces a URL ending in .json")
    func alwaysEndsInJSON() async throws {
        let docURL = try #require(URL(string: "https://developer.apple.com/documentation/SwiftUI"))
        let result = await defaultFetcher.buildAPIURL(from: docURL)
        #expect(result.absoluteString.hasSuffix(".json"))
    }
}
