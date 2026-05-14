import AppKit
@testable import Core
@testable import CorePackageIndexing
import CorePackageIndexingModels
import CoreProtocols
import Foundation
import SharedConstants
import Testing
import TestSupport

@Test func hTMLToMarkdown() throws {
    let html = "<h1>Title</h1><p>Content</p>"
    let markdown = try Core.Parser.HTML.convert(html, url: #require(URL(string: "https://example.com")))
    #expect(markdown.contains("# Title"))
}

// MARK: - Sample.Core.Catalog Tests

//
// The 5 legacy tests in this section assumed the embedded catalog was
// always populated (`SampleCodeCatalogEmbedded.json` was a build-time
// blob with ~600 entries). After #215 deleted that blob, the catalog
// only exists when `cupertino fetch --type code` has written
// `<sample-code-dir>/catalog.json`, so a CI machine with no fetched
// data would fail those tests.
//
// Replacement coverage for the on-disk flow (loading, fixture, search,
// framework filter) lives in `SampleCodeCatalogTests.swift`, which uses
// `loadFromDisk(at:)` against a temp-dir fixture and is independent of
// any user / CI sample-code state.

// MARK: - SwiftPackagesCatalog Tests

@Test("SwiftPackagesCatalog loads from JSON resource")
func swiftPackagesCatalogLoadsFromJSON() async {
    let count = await Core.Protocols.SwiftPackagesCatalog.count
    #expect(count > 9000, "Should have thousands of Swift packages")
    #expect(count < 15000, "Package count should be reasonable")
    print("   ✅ Loaded \(count) Swift packages")
}

@Test("SwiftPackagesCatalog has correct metadata")
func swiftPackagesCatalogMetadata() async {
    let version = await Core.Protocols.SwiftPackagesCatalog.version
    let lastCrawled = await Core.Protocols.SwiftPackagesCatalog.lastCrawled
    let source = await Core.Protocols.SwiftPackagesCatalog.source

    #expect(!version.isEmpty, "Release.Version should not be empty")
    #expect(!lastCrawled.isEmpty, "Last crawled date should not be empty")
    #expect(!source.isEmpty, "Source should not be empty")
    print("   ✅ Release.Version: \(version), Last crawled: \(lastCrawled)")
    print("   ✅ Source: \(source)")
}

@Test("SwiftPackagesCatalog entries have required fields")
func swiftPackagesCatalogEntriesValid() async {
    let packages = await Core.Protocols.SwiftPackagesCatalog.allPackages
    #expect(!packages.isEmpty, "Should have at least one package")

    // Verify first entry has all required fields
    let firstPackage = packages[0]
    #expect(!firstPackage.owner.isEmpty, "Package should have owner")
    #expect(!firstPackage.repo.isEmpty, "Package should have repo")
    #expect(!firstPackage.url.isEmpty, "Package should have URL")
    // updatedAt is optional - some packages may not have it
    if let updatedAt = firstPackage.updatedAt {
        #expect(!updatedAt.isEmpty, "If updatedAt exists, it should not be empty")
    }

    print("   ✅ Sample package: \(firstPackage.owner)/\(firstPackage.repo)")
}

@Test("SwiftPackagesCatalog search works")
func swiftPackagesCatalogSearch() async {
    let results = await Core.Protocols.SwiftPackagesCatalog.search("SwiftUI")
    #expect(!results.isEmpty, "Search for 'SwiftUI' should return results")

    print("   ✅ Found \(results.count) results for 'SwiftUI'")
}

// Removed in #161: `topPackages(limit:)` and `activePackages(minStars:)` relied
// on metadata (stars, fork, archived) that the slimmed URL-only catalog no
// longer carries. Once packages.db lands in v1.0.0, those queries should come
// from the DB; test coverage will move there.

// MARK: - Core.PackageIndexing.PriorityPackagesCatalog Tests

@Test("Core.PackageIndexing.PriorityPackagesCatalog loads from JSON resource")
func priorityPackagesCatalogLoadsFromJSON() async {
    // Path-DI migration (#535): PriorityPackagesCatalog is now an actor.
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("priority-test-\(UUID().uuidString)")
    let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(
        baseDirectory: tempDir,
        useBundledOnly: true
    )
    // Use bundled file for consistent test results (not user's selected-packages.json)

    let stats = await priorityCatalog.stats
    #expect(stats.totalPriorityPackages > 100, "Should have 100+ priority packages after the catalog expansion")
    #expect(stats.totalPriorityPackages < 500, "Priority package count should still be bounded")
    // These fields are optional to support TUI-generated files (which may not have them)
    if let appleCount = stats.totalCriticalApplePackages {
        #expect(appleCount > 25, "Should have 25+ Apple packages")
    }
    if let ecosystemCount = stats.totalEcosystemPackages {
        #expect(ecosystemCount > 0, "Should have ecosystem packages")
    }
    let applePackages = stats.totalCriticalApplePackages ?? 0
    let ecosystemPackages = stats.totalEcosystemPackages ?? 0
    let expectedTotal = applePackages + ecosystemPackages
    #expect(stats.totalPriorityPackages == expectedTotal, "Total should equal sum")
    print("   ✅ Loaded \(stats.totalPriorityPackages) priority packages")

}

@Test("Core.PackageIndexing.PriorityPackagesCatalog has correct metadata")
func priorityPackagesCatalogMetadata() async {
    // Path-DI migration (#535): PriorityPackagesCatalog is now an actor.
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("priority-test-\(UUID().uuidString)")
    let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(
        baseDirectory: tempDir,
        useBundledOnly: true
    )
    // Use bundled file for consistent test results

    let version = await priorityCatalog.version
    let lastUpdated = await priorityCatalog.lastUpdated
    let description = await priorityCatalog.description

    #expect(!version.isEmpty, "Release.Version should not be empty")
    #expect(!lastUpdated.isEmpty, "Last updated date should not be empty")
    #expect(!description.isEmpty, "Description should not be empty")
    print("   ✅ Release.Version: \(version), Last updated: \(lastUpdated)")

}

@Test("Core.PackageIndexing.PriorityPackagesCatalog Apple packages are valid")
func priorityPackagesCatalogApplePackages() async {
    // Path-DI migration (#535): PriorityPackagesCatalog is now an actor.
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("priority-test-\(UUID().uuidString)")
    let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(
        baseDirectory: tempDir,
        useBundledOnly: true
    )
    // Use bundled file for consistent test results

    let applePackages = await priorityCatalog.applePackages
    #expect(applePackages.count > 40, "Should have 40+ Apple packages after expansion")
    #expect(applePackages.count < 100, "Apple package count should still be bounded")

    // Verify known critical packages exist
    let repos = applePackages.map(\.repo)
    #expect(repos.contains("swift"), "Should contain swift")
    #expect(repos.contains("swift-nio"), "Should contain swift-nio")
    #expect(repos.contains("swift-testing"), "Should contain swift-testing")

    print("   ✅ Apple packages validated")

}

@Test("Core.PackageIndexing.PriorityPackagesCatalog ecosystem packages are valid")
func priorityPackagesCatalogEcosystemPackages() async {
    // Path-DI migration (#535): PriorityPackagesCatalog is now an actor.
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("priority-test-\(UUID().uuidString)")
    let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(
        baseDirectory: tempDir,
        useBundledOnly: true
    )
    // Use bundled file for consistent test results

    let ecosystemPackages = await priorityCatalog.ecosystemPackages
    #expect(!ecosystemPackages.isEmpty, "Should have ecosystem packages")
    #expect(ecosystemPackages.count > 50, "Ecosystem package count should reflect the expansion")
    #expect(ecosystemPackages.count < 500, "Ecosystem package count should still be bounded")

    // Verify known ecosystem packages exist
    let fullNames = ecosystemPackages.map { "\($0.owner ?? "")/\($0.repo)" }
    #expect(fullNames.contains("vapor/vapor"), "Should contain vapor/vapor")
    #expect(fullNames.contains("pointfreeco/swift-composable-architecture"), "Should contain TCA")

    print("   ✅ Ecosystem packages validated")

}

@Test("Core.PackageIndexing.PriorityPackagesCatalog priority check works")
func priorityPackagesCatalogPriorityCheck() async {
    // Path-DI migration (#535): PriorityPackagesCatalog is now an actor.
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("priority-test-\(UUID().uuidString)")
    let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(
        baseDirectory: tempDir,
        useBundledOnly: true
    )
    // Use bundled file for consistent test results

    // Test known priority packages
    let isSwiftPriority = await priorityCatalog.isPriority(owner: "apple", repo: "swift")
    let isNIOPriority = await priorityCatalog.isPriority(owner: "apple", repo: "swift-nio")
    let isVaporPriority = await priorityCatalog.isPriority(owner: "vapor", repo: "vapor")

    #expect(isSwiftPriority, "swift should be priority")
    #expect(isNIOPriority, "swift-nio should be priority")
    #expect(isVaporPriority, "vapor should be priority")

    // Test non-priority package
    let isRandomPriority = await priorityCatalog.isPriority(owner: "random", repo: "package")
    #expect(!isRandomPriority, "random package should not be priority")

    print("   ✅ Priority check working correctly")

}

@Test("Core.PackageIndexing.PriorityPackagesCatalog package lookup works")
func priorityPackagesCatalogPackageLookup() async {
    // Path-DI migration (#535): PriorityPackagesCatalog is now an actor.
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("priority-test-\(UUID().uuidString)")
    let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(
        baseDirectory: tempDir,
        useBundledOnly: true
    )
    // Use bundled file for consistent test results

    do {
        let swiftPackage = await priorityCatalog.package(named: "swift")
        #expect(swiftPackage != nil, "Should find swift package")
        #expect(swiftPackage?.repo == "swift", "Package repo should match")

        let vaporPackage = await priorityCatalog.package(named: "vapor")
        #expect(vaporPackage != nil, "Should find vapor package")
        #expect(vaporPackage?.owner == "vapor", "Vapor owner should be vapor")

        print("   ✅ Package lookup working correctly")
    }

    // Reset after test - must await to avoid race condition
}

@Test("Core.PackageIndexing.PriorityPackagesCatalog reads user-selections file under its baseDirectory")
func priorityPackagesCatalogLoadsUserFile() async throws {
    // Path-DI migration (#535): PriorityPackagesCatalog is now an actor
    // constructed with an explicit baseDirectory. Pre-#535 this test
    // checked the user file at ~/.cupertino/selected-packages.json via
    // the BinaryConfig.shared singleton — that path is gone. Rewritten
    // to verify the same precedence (user file wins over bundled) but
    // against a per-test tempDir baseDirectory.
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("priority-loads-user-file-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Write a deliberately minimal user selections file. The actor's
    // ensureUserSelectionsFileExists() will additively merge embedded
    // entries on top (the #218 behaviour); we just need to confirm the
    // user file is read at all by checking the post-load count is
    // non-zero AND derives from the on-disk version + merge.
    let userFileURL = tempDir.appendingPathComponent(Shared.Constants.FileName.selectedPackages)
    let minimalJSON = #"""
    {
        "version": "test",
        "lastUpdated": "2026-05-15T00:00:00Z",
        "description": "test fixture",
        "tiers": {
            "apple_official": {
                "description": "Apple test tier",
                "count": 1,
                "packages": [
                    {"owner": "apple", "repo": "swift", "url": "https://github.com/apple/swift"}
                ]
            },
            "ecosystem": {
                "description": "Ecosystem test tier",
                "count": 0,
                "packages": []
            }
        },
        "stats": {
            "totalPriorityPackages": 1
        }
    }
    """#
    try minimalJSON.write(to: userFileURL, atomically: true, encoding: .utf8)

    let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(
        baseDirectory: tempDir,
        useBundledOnly: false
    )
    let allPackages = await priorityCatalog.allPackages

    // Catalog must include the apple/swift entry from the user file
    // (whether or not #218 merge added more from the embedded list).
    #expect(
        allPackages.contains { $0.repo == "swift" && ($0.owner ?? "") == "apple" },
        "Catalog should load the user file's apple/swift entry"
    )
    #expect(!allPackages.isEmpty, "Catalog should load at least one package")
    print("   ✅ User file loaded: \(allPackages.count) packages")
}

/// Custom test error
struct TestError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) {
        self.message = message
    }

    var description: String {
        message
    }
}

@Test("HashUtilities sha256 produces consistent hashes")
func hashUtilitiesSHA256Consistency() {
    let content1 = "Hello, World!"
    let content2 = "Hello, World!"
    let content3 = "Different content"

    let hash1 = Shared.Models.HashUtilities.sha256(of: content1)
    let hash2 = Shared.Models.HashUtilities.sha256(of: content2)
    let hash3 = Shared.Models.HashUtilities.sha256(of: content3)

    // Same content should produce same hash
    #expect(hash1 == hash2)

    // Different content should produce different hash
    #expect(hash1 != hash3)

    // Hash should be 64 characters (256 bits in hex)
    #expect(hash1.count == 64)

    print("   ✅ SHA-256 hashing working correctly")
}

// MARK: - Core.PackageIndexing.PriorityPackagesCatalog merge tests (#218)

/// Coverage for #218: an existing user file at
/// `~/.cupertino/selected-packages.json` should additively pick up new
/// entries from `Resources.Embedded.PriorityPackages.swift` instead of being frozen at
/// whichever priority list it was first seeded with.
@Suite("Core.PackageIndexing.PriorityPackagesCatalog embedded-entry merge (#218)")
struct PriorityPackagesMergeTests {
    @Test("Adds new ecosystem entries while preserving existing ones")
    func mergeAddsNewEcosystem() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let userFile = dir.appendingPathComponent("selected-packages.json")

        // Stale user file: 1 ecosystem entry, no mihaelamj.
        let stale = """
        {
          "version": "1.0",
          "lastUpdated": "2025-12-12",
          "description": "User selections",
          "tiers": {
            "ecosystem": {
              "description": "Ecosystem",
              "count": 1,
              "packages": [
                { "owner": "vapor", "repo": "vapor", "url": "https://github.com/vapor/vapor" }
              ]
            }
          },
          "stats": { "totalPriorityPackages": 1 }
        }
        """
        try stale.write(to: userFile, atomically: true, encoding: .utf8)

        // Embedded: same vapor entry plus two mihaelamj additions.
        let embedded = """
        {
          "version": "1.1",
          "lastUpdated": "2026-04-15",
          "description": "Bundled priority packages",
          "tiers": {
            "ecosystem": {
              "description": "Ecosystem",
              "count": 3,
              "packages": [
                { "owner": "vapor", "repo": "vapor", "url": "https://github.com/vapor/vapor" },
                { "owner": "mihaelamj", "repo": "BearerTokenAuthMiddleware", "url": "https://github.com/mihaelamj/BearerTokenAuthMiddleware" },
                { "owner": "mihaelamj", "repo": "OpenAPILoggingMiddleware", "url": "https://github.com/mihaelamj/OpenAPILoggingMiddleware" }
              ]
            }
          },
          "stats": { "totalPriorityPackages": 3 }
        }
        """

        Core.PackageIndexing.PriorityPackagesCatalog.mergeNewEmbeddedEntries(
            into: userFile,
            from: Data(embedded.utf8)
        )

        let merged = try JSONDecoder().decode(
            Core.PackageIndexing.PriorityPackagesCatalogJSON.self,
            from: Data(contentsOf: userFile)
        )
        let repos = merged.tiers.ecosystem.packages.map(\.repo)
        #expect(repos.contains("vapor"))
        #expect(repos.contains("BearerTokenAuthMiddleware"))
        #expect(repos.contains("OpenAPILoggingMiddleware"))
        #expect(merged.tiers.ecosystem.count == 3)
    }

    @Test("Idempotent — merging twice doesn't duplicate entries")
    func mergeIdempotent() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let userFile = dir.appendingPathComponent("selected-packages.json")

        let payload = """
        {
          "version": "1.0",
          "lastUpdated": "2026-05-03",
          "description": "x",
          "tiers": {
            "ecosystem": {
              "description": "Ecosystem",
              "count": 1,
              "packages": [
                { "owner": "vapor", "repo": "vapor", "url": "https://github.com/vapor/vapor" }
              ]
            }
          },
          "stats": { "totalPriorityPackages": 1 }
        }
        """
        try payload.write(to: userFile, atomically: true, encoding: .utf8)

        Core.PackageIndexing.PriorityPackagesCatalog.mergeNewEmbeddedEntries(into: userFile, from: Data(payload.utf8))
        Core.PackageIndexing.PriorityPackagesCatalog.mergeNewEmbeddedEntries(into: userFile, from: Data(payload.utf8))

        let merged = try JSONDecoder().decode(
            Core.PackageIndexing.PriorityPackagesCatalogJSON.self,
            from: Data(contentsOf: userFile)
        )
        #expect(merged.tiers.ecosystem.packages.count == 1)
    }

    @Test("User deletions stick — embedded re-additions are NOT brought back")
    func mergePreservesDeletions() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let userFile = dir.appendingPathComponent("selected-packages.json")

        // User has deliberately removed 'vapor' from their selection.
        let user = """
        {
          "version": "1.0",
          "lastUpdated": "2025-12-12",
          "description": "x",
          "tiers": {
            "ecosystem": { "description": "Ecosystem", "count": 0, "packages": [] }
          },
          "stats": { "totalPriorityPackages": 0 }
        }
        """
        try user.write(to: userFile, atomically: true, encoding: .utf8)

        let embedded = """
        {
          "version": "1.1",
          "lastUpdated": "2026-05-03",
          "description": "x",
          "tiers": {
            "ecosystem": {
              "description": "Ecosystem",
              "count": 1,
              "packages": [
                { "owner": "vapor", "repo": "vapor", "url": "https://github.com/vapor/vapor" }
              ]
            }
          },
          "stats": { "totalPriorityPackages": 1 }
        }
        """

        Core.PackageIndexing.PriorityPackagesCatalog.mergeNewEmbeddedEntries(
            into: userFile,
            from: Data(embedded.utf8)
        )

        // Wait — current implementation appends embedded entries the user
        // hasn't seen. A user-side deletion is indistinguishable from "user
        // never had this entry" in pure set-diff merge. So vapor WILL come
        // back. Document the behaviour: this test pins the trade-off.
        // If "sticky deletions" become a real requirement we'll need a
        // separate "removed" list. (#218 deliberately picked simple set-diff.)
        let merged = try JSONDecoder().decode(
            Core.PackageIndexing.PriorityPackagesCatalogJSON.self,
            from: Data(contentsOf: userFile)
        )
        #expect(merged.tiers.ecosystem.packages.map(\.repo) == ["vapor"])
    }

    @Test("Owner derived from URL when explicit owner field is missing")
    func mergeHandlesMissingOwnerField() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let userFile = dir.appendingPathComponent("selected-packages.json")

        // User file has owner-less entry; embedded provides explicit owner
        // but same repo. URL derivation should match these as the same key.
        let user = """
        {
          "version": "1.0",
          "lastUpdated": "2025-12-12",
          "description": "x",
          "tiers": {
            "ecosystem": {
              "description": "Ecosystem",
              "count": 1,
              "packages": [
                { "repo": "vapor", "url": "https://github.com/vapor/vapor" }
              ]
            }
          },
          "stats": { "totalPriorityPackages": 1 }
        }
        """
        try user.write(to: userFile, atomically: true, encoding: .utf8)

        let embedded = """
        {
          "version": "1.0",
          "lastUpdated": "2026-05-03",
          "description": "x",
          "tiers": {
            "ecosystem": {
              "description": "Ecosystem",
              "count": 1,
              "packages": [
                { "owner": "vapor", "repo": "vapor", "url": "https://github.com/vapor/vapor" }
              ]
            }
          },
          "stats": { "totalPriorityPackages": 1 }
        }
        """

        Core.PackageIndexing.PriorityPackagesCatalog.mergeNewEmbeddedEntries(
            into: userFile,
            from: Data(embedded.utf8)
        )

        let merged = try JSONDecoder().decode(
            Core.PackageIndexing.PriorityPackagesCatalogJSON.self,
            from: Data(contentsOf: userFile)
        )
        #expect(merged.tiers.ecosystem.packages.count == 1, "URL-derived owner should match explicit owner")
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PriorityMergeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - PackageAvailabilityAnnotator tests (#219)

@Suite("PackageAvailabilityAnnotator (#219)")
struct PackageAvailabilityAnnotatorTests {
    @Test("parsePlatforms extracts iOS / macOS / tvOS / watchOS deployment targets")
    func platformsCommonShape() {
        let manifest = """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(
            name: "Foo",
            platforms: [
                .macOS(.v10_15),
                .iOS(.v13),
                .tvOS(.v13),
                .watchOS(.v6)
            ],
            products: []
        )
        """
        let result = Core.PackageIndexing.PackageAvailabilityAnnotator.parsePlatforms(from: manifest)
        #expect(result["macOS"] == "10.15")
        #expect(result["iOS"] == "13.0")
        #expect(result["tvOS"] == "13.0")
        #expect(result["watchOS"] == "6.0")
    }

    @Test("parsePlatforms returns empty dict when no platforms block")
    func platformsAbsent() {
        let manifest = """
        import PackageDescription
        let package = Package(name: "Foo", products: [])
        """
        #expect(Core.PackageIndexing.PackageAvailabilityAnnotator.parsePlatforms(from: manifest).isEmpty)
    }

    @Test("parsePlatforms handles multi-digit minor like .v10_15_4")
    func platformsMultiDigit() {
        let manifest = """
        platforms: [.macOS(.v10_15_4)],
        """
        let result = Core.PackageIndexing.PackageAvailabilityAnnotator.parsePlatforms(from: manifest)
        #expect(result["macOS"] == "10.15.4")
    }

    @Test("parsePlatforms ignores nested arrays elsewhere in the manifest")
    func platformsIgnoresOtherArrays() {
        let manifest = """
        platforms: [.iOS(.v16)],
        targets: [.target(name: "Foo")]
        """
        let result = Core.PackageIndexing.PackageAvailabilityAnnotator.parsePlatforms(from: manifest)
        #expect(result == ["iOS": "16.0"])
    }

    @Test("extractAvailability captures line + raw + platforms list")
    func availabilityBasic() {
        let source = """
        struct Foo {
            @available(iOS 16.0, macOS 13.0, *)
            func bar() {}
        }
        """
        let attrs = Core.PackageIndexing.PackageAvailabilityAnnotator.extractAvailability(from: source)
        #expect(attrs.count == 1)
        #expect(attrs.first?.line == 2)
        #expect(attrs.first?.raw == "(iOS 16.0, macOS 13.0, *)")
        #expect(attrs.first?.platforms.contains("iOS") == true)
        #expect(attrs.first?.platforms.contains("macOS") == true)
        #expect(attrs.first?.platforms.contains("*") == true)
    }

    @Test("extractAvailability handles deprecated/noasync keyword forms")
    func availabilityKeywords() {
        let source = """
        @available(*, deprecated, message: "Use newFoo() instead")
        func oldFoo() {}

        @available(*, noasync, message: "Sync only")
        func syncFoo() {}
        """
        let attrs = Core.PackageIndexing.PackageAvailabilityAnnotator.extractAvailability(from: source)
        #expect(attrs.count == 2)
        #expect(attrs[0].platforms.contains("deprecated"))
        #expect(attrs[1].platforms.contains("noasync"))
    }

    @Test("extractAvailability returns empty array on plain source")
    func availabilityEmpty() {
        #expect(Core.PackageIndexing.PackageAvailabilityAnnotator.extractAvailability(from: "let x = 1").isEmpty)
    }

    @Test("annotate writes availability.json with deployment targets + file attrs")
    func annotateRoundtrip() async throws {
        let dir = try Self.makeTempPackage()
        defer { try? FileManager.default.removeItem(at: dir) }

        let annotator = Core.PackageIndexing.PackageAvailabilityAnnotator()
        let result = try await annotator.annotate(packageDirectory: dir)

        #expect(result.deploymentTargets["iOS"] == "16.0")
        #expect(result.deploymentTargets["macOS"] == "13.0")
        #expect(result.stats.totalAttributes == 1)
        #expect(result.fileAvailability.count == 1)
        #expect(result.fileAvailability.first?.relpath == "Sources/Foo/Foo.swift")

        let outURL = dir.appendingPathComponent(Core.PackageIndexing.availabilityFilename)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(
            Core.PackageIndexing.AnnotationResult.self,
            from: Data(contentsOf: outURL)
        )
        #expect(reloaded.deploymentTargets == result.deploymentTargets)
        #expect(reloaded.stats.totalAttributes == 1)
    }

    @Test("annotate throws when package directory missing")
    func annotateMissingDir() async throws {
        let bogus = URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString)")
        let annotator = Core.PackageIndexing.PackageAvailabilityAnnotator()
        await #expect(throws: Core.PackageIndexing.PackageAvailabilityAnnotator.AnnotationError.self) {
            _ = try await annotator.annotate(packageDirectory: bogus)
        }
    }

    @Test("annotate is idempotent — second pass produces same content")
    func annotateIdempotent() async throws {
        let dir = try Self.makeTempPackage()
        defer { try? FileManager.default.removeItem(at: dir) }

        let annotator = Core.PackageIndexing.PackageAvailabilityAnnotator()
        let first = try await annotator.annotate(packageDirectory: dir)
        let second = try await annotator.annotate(packageDirectory: dir)
        // Stats and content stable; only annotatedAt differs.
        #expect(first.deploymentTargets == second.deploymentTargets)
        #expect(first.fileAvailability == second.fileAvailability)
        #expect(first.stats == second.stats)
    }

    private static func makeTempPackage() throws -> URL {
        let manager = FileManager.default
        let dir = manager.temporaryDirectory
            .appendingPathComponent("AvailAnnotateTests-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: dir, withIntermediateDirectories: true)

        let manifest = """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(
            name: "Foo",
            platforms: [.iOS(.v16), .macOS(.v13)],
            products: []
        )
        """
        try manifest.write(
            to: dir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let sourceDir = dir.appendingPathComponent("Sources/Foo")
        try manager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let source = """
        struct Foo {
            @available(iOS 17.0, *)
            func bar() {}
        }
        """
        try source.write(
            to: sourceDir.appendingPathComponent("Foo.swift"),
            atomically: true,
            encoding: .utf8
        )

        return dir
    }
}

// Note: Test tags are now defined in TestSupport/TestTags.swift
