@testable import Core
import Foundation
import Testing
import CoreProtocols

/// Coverage for #214: `SampleCodeCatalog` should prefer the on-disk
/// `catalog.json` (written by `cupertino fetch --type code`) over the
/// embedded snapshot, and gracefully fall back when the on-disk file is
/// missing or malformed. Also covers
/// `SampleCodeDownloader.transformAppleListingToCatalog`.
@Suite("SampleCodeCatalog disk-first loading (#214)")
struct SampleCodeCatalogTests {
    // MARK: - loadFromDisk

    @Test("loadFromDisk returns nil when no file exists at the path")
    func diskMissing() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SampleCodeCatalog.loadFromDisk(at: dir) == nil)
    }

    @Test("loadFromDisk returns nil when catalog.json is malformed")
    func diskMalformed() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeCatalog(in: dir, contents: "{ this is not valid json")
        #expect(SampleCodeCatalog.loadFromDisk(at: dir) == nil)
    }

    @Test("loadFromDisk decodes a valid catalog.json")
    func diskValid() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeCatalog(in: dir, contents: Self.validCatalogJSON(count: 2))
        let catalog = SampleCodeCatalog.loadFromDisk(at: dir)
        #expect(catalog != nil)
        #expect(catalog?.count == 2)
        #expect(catalog?.entries.count == 2)
        #expect(catalog?.entries.first?.title == "Sample One")
        #expect(catalog?.entries.first?.framework == "Foundation")
    }

    @Test("loadFromDisk uses default sample-code dir when no path is provided")
    func diskDefaultPath() {
        // Just exercise the default-arg overload — no file there in test env,
        // expect nil rather than a crash.
        _ = SampleCodeCatalog.loadFromDisk()
    }

    // MARK: - loadCatalog (end-to-end via allEntries)

    //
    // After #215 there is no embedded fallback. Missing on-disk catalog
    // → empty entries + .missing source.

    @Test("allEntries returns empty + .missing source when no on-disk catalog")
    func endToEndMissing() async {
        await SampleCodeCatalog.resetCache()
        // The test machine MAY have ~/.cupertino-dev/sample-code/catalog.json,
        // in which case loadedSource is .onDisk and entries is non-empty.
        // On a fresh CI machine it should be .missing with no entries.
        let entries = await SampleCodeCatalog.allEntries
        let source = await SampleCodeCatalog.loadedSource
        switch source {
        case .onDisk:
            #expect(!entries.isEmpty)
        case .missing:
            #expect(entries.isEmpty)
        case .none:
            Issue.record("loadedSource should be set after first allEntries access")
        }
    }

    // MARK: - SampleCodeDownloader.transformAppleListingToCatalog

    @Test("transformAppleListingToCatalog returns nil for non-JSON input")
    func transformInvalid() {
        let bytes = Data("not json".utf8)
        #expect(SampleCodeDownloader.transformAppleListingToCatalog(data: bytes) == nil)
    }

    @Test("transformAppleListingToCatalog returns nil when references key missing")
    func transformMissingRefs() {
        let json = Data("""
        { "metadata": { "title": "Sample Code" } }
        """.utf8)
        #expect(SampleCodeDownloader.transformAppleListingToCatalog(data: json) == nil)
    }

    @Test("transformAppleListingToCatalog filters to role=sampleCode entries")
    func transformFiltersByRole() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: true).utf8)
        let catalog = try #require(SampleCodeDownloader.transformAppleListingToCatalog(data: json))
        // Fixture has 2 sampleCode + 1 article; only the 2 should land
        #expect(catalog.count == 2)
        #expect(catalog.entries.allSatisfy { !$0.title.isEmpty })
    }

    @Test("transformAppleListingToCatalog extracts framework from URL path")
    func transformExtractsFramework() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(SampleCodeDownloader.transformAppleListingToCatalog(data: json))
        let frameworks = Set(catalog.entries.map(\.framework))
        #expect(frameworks.contains("Foundation"))
        #expect(frameworks.contains("RealityKit"))
    }

    @Test("transformAppleListingToCatalog assembles webURL + zipFilename")
    func transformDerivedFields() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(SampleCodeDownloader.transformAppleListingToCatalog(data: json))
        let foundationEntry = try #require(catalog.entries.first { $0.framework == "Foundation" })
        #expect(foundationEntry.webURL.hasPrefix("https://developer.apple.com/documentation/Foundation/"))
        #expect(foundationEntry.zipFilename.hasPrefix("foundation-"))
        #expect(foundationEntry.zipFilename.hasSuffix(".zip"))
    }

    @Test("transformAppleListingToCatalog sorts by (framework, title)")
    func transformSortsStably() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(SampleCodeDownloader.transformAppleListingToCatalog(data: json))
        let frameworks = catalog.entries.map(\.framework)
        // Assert sorted
        #expect(frameworks == frameworks.sorted())
    }

    // MARK: - SampleCodeDownloader.writeCatalog (extracted disk-write step)

    @Test("writeCatalog round-trips through disk")
    func writeCatalogRoundTrip() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalogURL = dir.appendingPathComponent(SampleCodeCatalog.onDiskCatalogFilename)

        let original = try #require(
            SampleCodeDownloader.transformAppleListingToCatalog(
                data: Data(Self.appleListingFixture(includeNonSamples: false).utf8)
            )
        )

        try SampleCodeDownloader.writeCatalog(original, to: catalogURL)

        // File exists with non-zero size
        let attrs = try FileManager.default.attributesOfItem(atPath: catalogURL.path)
        #expect((attrs[.size] as? Int ?? 0) > 0)

        // Re-load through SampleCodeCatalog.loadFromDisk → byte-equivalent catalog
        let reloaded = try #require(SampleCodeCatalog.loadFromDisk(at: dir))
        #expect(reloaded.count == original.count)
        #expect(reloaded.entries.map(\.title) == original.entries.map(\.title))
        #expect(reloaded.entries.map(\.framework) == original.entries.map(\.framework))
    }

    @Test("writeCatalog overwrites existing catalog.json atomically")
    func writeCatalogOverwrite() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalogURL = dir.appendingPathComponent(SampleCodeCatalog.onDiskCatalogFilename)

        // Pre-existing junk content at the target path
        try "stale junk".write(to: catalogURL, atomically: true, encoding: .utf8)
        #expect(try Data(contentsOf: catalogURL) == Data("stale junk".utf8))

        // Write a real catalog over it
        let real = try #require(
            SampleCodeDownloader.transformAppleListingToCatalog(
                data: Data(Self.appleListingFixture(includeNonSamples: false).utf8)
            )
        )
        try SampleCodeDownloader.writeCatalog(real, to: catalogURL)

        // Old content gone, new content parses
        let reloaded = try #require(SampleCodeCatalog.loadFromDisk(at: dir))
        #expect(!reloaded.entries.isEmpty)
    }

    // MARK: - allEntries with test-override directory (#215 integration)

    @Test("allEntries picks up the override directory's catalog.json")
    func endToEndOverrideHit() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeCatalog(in: dir, contents: Self.validCatalogJSON(count: 2))

        await SampleCodeCatalog.setTestOverrideDirectory(dir)
        await SampleCodeCatalog.resetCache()
        defer { Task { await SampleCodeCatalog.setTestOverrideDirectory(nil); await SampleCodeCatalog.resetCache() } }

        let entries = await SampleCodeCatalog.allEntries
        let source = await SampleCodeCatalog.loadedSource

        #expect(entries.count == 2)
        #expect(source == .onDisk)
        #expect(entries.first?.title == "Sample One")
    }

    @Test("allEntries reports .missing when override directory has no catalog")
    func endToEndOverrideMiss() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Intentionally no catalog.json written

        await SampleCodeCatalog.setTestOverrideDirectory(dir)
        await SampleCodeCatalog.resetCache()
        defer { Task { await SampleCodeCatalog.setTestOverrideDirectory(nil); await SampleCodeCatalog.resetCache() } }

        let entries = await SampleCodeCatalog.allEntries
        let source = await SampleCodeCatalog.loadedSource

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
        let url = dir.appendingPathComponent(SampleCodeCatalog.onDiskCatalogFilename)
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
