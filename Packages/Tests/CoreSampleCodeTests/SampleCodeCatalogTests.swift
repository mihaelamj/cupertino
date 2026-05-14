@testable import CoreSampleCode
import Foundation
import SharedConstants
import Testing

/// Coverage for #214: `Sample.Core.Catalog` should prefer the on-disk
/// `catalog.json` (written by `cupertino fetch --type code`) over the
/// embedded snapshot, and gracefully fall back when the on-disk file is
/// missing or malformed. Also covers
/// `Sample.Core.Downloader.transformAppleListingToCatalog`.
@Suite("Sample.Core.Catalog disk-first loading (#214)")
struct SampleCodeCatalogTests {
    // MARK: - loadFromDisk

    @Test("hasParseableCatalog returns false when no file exists at the path")
    func diskMissing() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!Sample.Core.Catalog.hasParseableCatalog(at: dir))
    }

    @Test("hasParseableCatalog returns false when catalog.json is malformed")
    func diskMalformed() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeCatalog(in: dir, contents: "{ this is not valid json")
        #expect(!Sample.Core.Catalog.hasParseableCatalog(at: dir))
    }

    @Test("Catalog actor decodes a valid catalog.json")
    func diskValid() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeCatalog(in: dir, contents: Self.validCatalogJSON(count: 2))
        // Post-#535: catalog is an actor; verify end-to-end via the
        // public surface rather than reaching for the internal
        // SampleCodeCatalogJSON shape.
        let catalog = Sample.Core.Catalog(sampleCodeDirectory: dir)
        let count = await catalog.count
        let entries = await catalog.allEntries
        #expect(count == 2)
        #expect(entries.count == 2)
        #expect(entries.first?.title == "Sample One")
        #expect(entries.first?.framework == "Foundation")
    }

    // MARK: - loadCatalog (end-to-end via allEntries)

    //
    // After #215 there is no embedded fallback. Missing on-disk catalog
    // → empty entries + .missing source.

    @Test("allEntries returns empty + .missing source when no on-disk catalog")
    func endToEndMissing() async throws {
        // Post-#535: construct a catalog with an explicit empty tempDir
        // so the test is isolated from any real ~/.cupertino state.
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = Sample.Core.Catalog(sampleCodeDirectory: dir)
        let entries = await catalog.allEntries
        let source = await catalog.loadedSource
        #expect(entries.isEmpty)
        #expect(source == .missing)
    }

    // MARK: - Sample.Core.Downloader.transformAppleListingToCatalog

    @Test("transformAppleListingToCatalog returns nil for non-JSON input")
    func transformInvalid() {
        let bytes = Data("not json".utf8)
        #expect(Sample.Core.Downloader.transformAppleListingToCatalog(data: bytes) == nil)
    }

    @Test("transformAppleListingToCatalog returns nil when references key missing")
    func transformMissingRefs() {
        let json = Data("""
        { "metadata": { "title": "Sample Code" } }
        """.utf8)
        #expect(Sample.Core.Downloader.transformAppleListingToCatalog(data: json) == nil)
    }

    @Test("transformAppleListingToCatalog filters to role=sampleCode entries")
    func transformFiltersByRole() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: true).utf8)
        let catalog = try #require(Sample.Core.Downloader.transformAppleListingToCatalog(data: json))
        // Fixture has 2 sampleCode + 1 article; only the 2 should land
        #expect(catalog.count == 2)
        #expect(catalog.entries.allSatisfy { !$0.title.isEmpty })
    }

    @Test("transformAppleListingToCatalog extracts framework from URL path")
    func transformExtractsFramework() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(Sample.Core.Downloader.transformAppleListingToCatalog(data: json))
        let frameworks = Set(catalog.entries.map(\.framework))
        #expect(frameworks.contains("Foundation"))
        #expect(frameworks.contains("RealityKit"))
    }

    @Test("transformAppleListingToCatalog assembles webURL + zipFilename")
    func transformDerivedFields() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(Sample.Core.Downloader.transformAppleListingToCatalog(data: json))
        let foundationEntry = try #require(catalog.entries.first { $0.framework == "Foundation" })
        #expect(foundationEntry.webURL.hasPrefix("https://developer.apple.com/documentation/Foundation/"))
        #expect(foundationEntry.zipFilename.hasPrefix("foundation-"))
        #expect(foundationEntry.zipFilename.hasSuffix(".zip"))
    }

    @Test("transformAppleListingToCatalog sorts by (framework, title)")
    func transformSortsStably() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(Sample.Core.Downloader.transformAppleListingToCatalog(data: json))
        let frameworks = catalog.entries.map(\.framework)
        // Assert sorted
        #expect(frameworks == frameworks.sorted())
    }

    // MARK: - Sample.Core.Downloader.writeCatalog (extracted disk-write step)

    @Test("writeCatalog round-trips through disk")
    func writeCatalogRoundTrip() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalogURL = dir.appendingPathComponent(Sample.Core.Catalog.onDiskCatalogFilename)

        let original = try #require(
            Sample.Core.Downloader.transformAppleListingToCatalog(
                data: Data(Self.appleListingFixture(includeNonSamples: false).utf8)
            )
        )

        try Sample.Core.Downloader.writeCatalog(original, to: catalogURL)

        // File exists with non-zero size
        let attrs = try FileManager.default.attributesOfItem(atPath: catalogURL.path)
        #expect((attrs[.size] as? Int ?? 0) > 0)

        // Re-load through Sample.Core.Catalog actor → byte-equivalent catalog
        let reloaded = Sample.Core.Catalog(sampleCodeDirectory: dir)
        let reloadedCount = await reloaded.count
        let reloadedEntries = await reloaded.allEntries
        #expect(reloadedCount == original.count)
        #expect(reloadedEntries.map(\.title) == original.entries.map(\.title))
        #expect(reloadedEntries.map(\.framework) == original.entries.map(\.framework))
    }

    @Test("writeCatalog overwrites existing catalog.json atomically")
    func writeCatalogOverwrite() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalogURL = dir.appendingPathComponent(Sample.Core.Catalog.onDiskCatalogFilename)

        // Pre-existing junk content at the target path
        try "stale junk".write(to: catalogURL, atomically: true, encoding: .utf8)
        #expect(try Data(contentsOf: catalogURL) == Data("stale junk".utf8))

        // Write a real catalog over it
        let real = try #require(
            Sample.Core.Downloader.transformAppleListingToCatalog(
                data: Data(Self.appleListingFixture(includeNonSamples: false).utf8)
            )
        )
        try Sample.Core.Downloader.writeCatalog(real, to: catalogURL)

        // Old content gone, new content parses
        let reloaded = Sample.Core.Catalog(sampleCodeDirectory: dir)
        let entries = await reloaded.allEntries
        #expect(!entries.isEmpty)
    }

    // MARK: - allEntries with per-instance directory (#215 / #535 integration)
    //
    // Pre-#535 these tests used `setTestOverrideDirectory` on a process-wide
    // singleton. Post-#535 the catalog is per-instance — each test just
    // constructs an actor with the directory it wants.

    @Test("Catalog actor picks up an on-disk catalog.json from its sample-code dir")
    func endToEndOverrideHit() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeCatalog(in: dir, contents: Self.validCatalogJSON(count: 2))

        let catalog = Sample.Core.Catalog(sampleCodeDirectory: dir)
        let entries = await catalog.allEntries
        let source = await catalog.loadedSource

        #expect(entries.count == 2)
        #expect(source == .onDisk)
        #expect(entries.first?.title == "Sample One")
    }

    @Test("Catalog actor reports .missing when its sample-code dir has no catalog")
    func endToEndOverrideMiss() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Intentionally no catalog.json written

        let catalog = Sample.Core.Catalog(sampleCodeDirectory: dir)
        let entries = await catalog.allEntries
        let source = await catalog.loadedSource

        #expect(entries.isEmpty)
        #expect(source == .missing)
    }

    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SampleCodeCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func writeCatalog(in dir: URL, contents: String) throws {
        let url = dir.appendingPathComponent(Sample.Core.Catalog.onDiskCatalogFilename)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func validCatalogJSON(count: Int) -> String {
        """
        {
          "version": "test",
          "lastCrawled": "2026-05-03T00:00:00Z",
          "count": \(count),
          "entries": [
            {
              "title": "Sample One",
              "url": "/documentation/Foundation/sample-one",
              "framework": "Foundation",
              "description": "First sample.",
              "zipFilename": "foundation-sample-one.zip",
              "webURL": "https://developer.apple.com/documentation/Foundation/sample-one"
            },
            {
              "title": "Sample Two",
              "url": "/documentation/RealityKit/sample-two",
              "framework": "RealityKit",
              "description": "Second sample.",
              "zipFilename": "realitykit-sample-two.zip",
              "webURL": "https://developer.apple.com/documentation/RealityKit/sample-two"
            }
          ]
        }
        """
    }

    private static func appleListingFixture(includeNonSamples: Bool) -> String {
        let nonSampleEntry = includeNonSamples ? """
        ,
        "doc://com.apple.documentation/documentation/Other/an-article": {
            "role": "article",
            "title": "Not a sample",
            "kind": "article",
            "url": "/documentation/Other/an-article"
        }
        """ : ""

        return """
        {
            "references": {
                "doc://com.apple.documentation/documentation/Foundation/zebra-sample": {
                    "role": "sampleCode",
                    "title": "Zebra Sample",
                    "kind": "article",
                    "url": "/documentation/Foundation/zebra-sample",
                    "abstract": [
                        { "type": "text", "text": "Zebra description." }
                    ]
                },
                "doc://com.apple.documentation/documentation/RealityKit/aardvark-sample": {
                    "role": "sampleCode",
                    "title": "Aardvark Sample",
                    "kind": "article",
                    "url": "/documentation/RealityKit/aardvark-sample",
                    "abstract": [
                        { "type": "text", "text": "Aardvark description." }
                    ]
                }\(nonSampleEntry)
            }
        }
        """
    }
}
