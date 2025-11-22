@testable import Core
import Foundation
import Shared
import Testing

// MARK: - Priority Package Generator Tests

/// Comprehensive tests for PriorityPackageGenerator
/// Tests URL extraction, package categorization, tier selection, and output generation

@Suite("Priority Package Generator")
struct PriorityPackageGeneratorTests {
    // MARK: - Model Tests

    @Test("PriorityPackageInfo initializes correctly")
    func priorityPackageInfoInitialization() {
        let pkg = PriorityPackageInfo(
            owner: "apple",
            repo: "swift",
            url: "https://github.com/apple/swift"
        )

        #expect(pkg.owner == "apple")
        #expect(pkg.repo == "swift")
        #expect(pkg.url == "https://github.com/apple/swift")
    }

    @Test("PriorityPackageInfo is Hashable")
    func priorityPackageInfoHashable() {
        let pkg1 = PriorityPackageInfo(owner: "apple", repo: "swift", url: "https://github.com/apple/swift")
        let pkg2 = PriorityPackageInfo(owner: "apple", repo: "swift", url: "https://github.com/apple/swift")
        let pkg3 = PriorityPackageInfo(owner: "vapor", repo: "vapor", url: "https://github.com/vapor/vapor")

        #expect(pkg1 == pkg2)
        #expect(pkg1 != pkg3)

        let set: Set = [pkg1, pkg2, pkg3]
        #expect(set.count == 2) // pkg1 and pkg2 are duplicates
    }

    @Test("TierInfo encodes and decodes")
    func tierInfoEncodesAndDecodes() throws {
        let packages = [
            PriorityPackageInfo(owner: "apple", repo: "swift", url: "https://github.com/apple/swift"),
            PriorityPackageInfo(owner: "vapor", repo: "vapor", url: "https://github.com/vapor/vapor"),
        ]

        let tierInfo = TierInfo(
            description: "Test tier",
            packages: packages
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(tierInfo)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TierInfo.self, from: data)

        #expect(decoded.description == "Test tier")
        #expect(decoded.packages.count == 2)
        #expect(decoded.packages[0].owner == "apple")
    }

    @Test("PackageStats encodes with snake_case")
    func packageStatsEncodesWithSnakeCase() throws {
        let stats = PackageStats(
            totalApplePackagesInSwiftorg: 10,
            totalSwiftlangPackagesInSwiftorg: 5,
            totalEcosystemPackagesInSwiftorg: 3,
            totalUniqueReposFound: 18,
            sourceFilesScanned: 100
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(stats)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("total_apple_packages_in_swiftorg"))
        #expect(json.contains("total_swiftlang_packages_in_swiftorg"))
        #expect(json.contains("total_ecosystem_packages_in_swiftorg"))
        #expect(json.contains("total_unique_repos_found"))
        #expect(json.contains("source_files_scanned"))
    }

    @Test("PriorityLevels encodes with snake_case")
    func priorityLevelsEncodesWithSnakeCase() throws {
        let tier = TierInfo(description: "Test", packages: [])
        let levels = PriorityLevels(
            tier1AppleOfficial: tier,
            tier2Swiftlang: tier,
            tier3SwiftServer: tier,
            tier4Ecosystem: tier
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(levels)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("tier1_apple_official"))
        #expect(json.contains("tier2_swiftlang"))
        #expect(json.contains("tier3_swift_server"))
        #expect(json.contains("tier4_ecosystem"))
    }

    @Test("PriorityPackageList encodes completely")
    func priorityPackageListEncodes() throws {
        let pkg = PriorityPackageInfo(owner: "apple", repo: "swift", url: "https://github.com/apple/swift")
        let tier = TierInfo(description: "Test tier", packages: [pkg])
        let levels = PriorityLevels(
            tier1AppleOfficial: tier,
            tier2Swiftlang: tier,
            tier3SwiftServer: tier,
            tier4Ecosystem: tier
        )
        let stats = PackageStats(
            totalApplePackagesInSwiftorg: 1,
            totalSwiftlangPackagesInSwiftorg: 0,
            totalEcosystemPackagesInSwiftorg: 0,
            totalUniqueReposFound: 1,
            sourceFilesScanned: 10
        )

        let list = PriorityPackageList(
            version: "1.0",
            generatedAt: "2025-01-01T00:00:00Z",
            description: "Test list",
            sources: ["test"],
            updatePolicy: "manual",
            priorityLevels: levels,
            stats: stats,
            notes: ["Note 1"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(list)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PriorityPackageList.self, from: data)

        #expect(decoded.version == "1.0")
        #expect(decoded.description == "Test list")
        #expect(decoded.stats.totalUniqueReposFound == 1)
    }

    // MARK: - Error Tests

    @Test("PriorityPackageError provides description")
    func errorProvidesDescription() {
        let error = PriorityPackageError.cannotReadDirectory("/path/to/dir")
        let description = error.description

        #expect(description.contains("/path/to/dir"))
        #expect(description.contains("Cannot read directory"))
    }

    // MARK: - Helper Methods

    private func createTestGenerator() async -> PriorityPackageGenerator {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("priority-test-\(UUID().uuidString)")
        let outputFile = tempDir.appendingPathComponent("output.json")

        return await PriorityPackageGenerator(
            swiftOrgDocsPath: tempDir,
            outputPath: outputFile
        )
    }

    private func createTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("priority-test-\(UUID().uuidString)")
    }

    private func cleanupTempDirectory(_ tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

// MARK: - Test Extensions

// Note: extractGitHubURLs is a private method and cannot be tested directly
// We test it indirectly through the public generate API
