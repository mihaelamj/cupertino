// This file loads the Apple Sample Code Library from JSON.
//
// Source of truth: `<sample-code-dir>/catalog.json` written by
// `cupertino fetch --type code` (Apple's `samplecode.json` listing
// transformed to the SampleCodeCatalogJSON shape). The previous
// embedded blob (SampleCodeCatalogEmbedded) was deleted in #215 —
// auto-discovery is the only path now.

import Foundation
import Shared

/// Represents a sample code project from Apple
public struct SampleCodeEntry: Codable, Sendable {
    public let title: String
    public let url: String
    public let framework: String
    public let description: String
    public let zipFilename: String
    public let webURL: String

    public init(
        title: String, url: String, framework: String,
        description: String, zipFilename: String, webURL: String
    ) {
        self.title = title
        self.url = url
        self.framework = framework
        self.description = description
        self.zipFilename = zipFilename
        self.webURL = webURL
    }
}

/// JSON structure for sample code catalog
struct SampleCodeCatalogJSON: Codable {
    let version: String
    let lastCrawled: String
    let count: Int
    let entries: [SampleCodeEntry]
}

/// Complete catalog of all Apple sample code projects.
///
/// Reads from `<sample-code-dir>/catalog.json` (written by
/// `cupertino fetch --type code`). Returns an empty catalog when no
/// on-disk file exists or it fails to decode — there is no embedded
/// fallback (#215). Callers (e.g. `SearchIndexBuilder`) should check
/// `loadedSource` and warn the user when the catalog is missing so the
/// fix is obvious: run fetch.
public enum SampleCodeCatalog {
    /// File name written by `SampleCodeDownloader` next to the fetched zips
    /// so `cupertino save` can pick up the freshly-discovered metadata.
    public static let onDiskCatalogFilename = "catalog.json"

    /// Source the catalog was loaded from on the most recent `loadCatalog`
    /// call. Useful for telling users via the build log whether their save
    /// is indexing real data or skipping for lack of input.
    public enum Source: String, Sendable {
        /// `<sample-code-dir>/catalog.json` was found and decoded successfully.
        case onDisk
        /// No on-disk catalog (file absent or unparseable). Caller should
        /// hint at running `cupertino fetch --type code` to populate it.
        case missing
    }

    /// Cached catalog data (thread-safe via actor isolation)
    private actor Cache {
        var catalog: SampleCodeCatalogJSON?
        var source: Source?

        func get() -> (SampleCodeCatalogJSON, Source)? {
            guard let catalog, let source else { return nil }
            return (catalog, source)
        }

        func set(_ newCatalog: SampleCodeCatalogJSON, source: Source) {
            catalog = newCatalog
            self.source = source
        }

        func clear() {
            catalog = nil
            source = nil
        }
    }

    private static let cache = Cache()

    /// Reset the cached catalog. Used by tests to force `loadCatalog` to
    /// re-evaluate disk state between cases.
    public static func resetCache() async {
        await cache.clear()
    }

    /// Load catalog from `<sample-code-dir>/catalog.json`. Returns an empty
    /// catalog if the file is missing or unparseable (#215: no embedded
    /// fallback). The result + source are cached for the process lifetime;
    /// call `resetCache` to re-evaluate. Honours
    /// `setTestOverrideDirectory` so integration tests can sandbox.
    private static func loadCatalog() async -> SampleCodeCatalogJSON {
        if let cached = await cache.get() {
            return cached.0
        }

        if let onDisk = await loadFromDiskRespectingOverride() {
            await cache.set(onDisk, source: .onDisk)
            return onDisk
        }

        let empty = SampleCodeCatalogJSON(
            version: "missing",
            lastCrawled: "",
            count: 0,
            entries: []
        )
        await cache.set(empty, source: .missing)
        return empty
    }

    /// Test-only override for the default sample-code directory. When set
    /// via `setTestOverrideDirectory`, `loadFromDisk()` (no-arg) reads from
    /// here instead of `Shared.Constants.defaultSampleCodeDirectory`. Lets
    /// integration tests sandbox without polluting user data and without
    /// requiring callers to plumb a directory through every API.
    /// Production code must never set this.
    private actor TestOverride {
        var directory: URL?
        func get() -> URL? {
            directory
        }

        func set(_ url: URL?) {
            directory = url
        }
    }

    private static let testOverride = TestOverride()

    /// Set a test-only override for the default sample-code directory.
    /// Pass `nil` to clear. `internal` so production code can't reach it.
    static func setTestOverrideDirectory(_ url: URL?) async {
        await testOverride.set(url)
    }

    /// Read `<sample-code-dir>/catalog.json` if present and parseable.
    /// `internal` so tests can drive it directly. The no-arg form reads
    /// from `Shared.Constants.defaultSampleCodeDirectory`; tests pass an
    /// explicit path or use the async `loadFromDiskRespectingOverride`
    /// below to honour the test override.
    static func loadFromDisk(at directory: URL? = nil) -> SampleCodeCatalogJSON? {
        let dir = directory ?? Shared.Constants.defaultSampleCodeDirectory
        let url = dir.appendingPathComponent(onDiskCatalogFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SampleCodeCatalogJSON.self, from: data)
    }

    /// Async load that respects the test override. Production code calls
    /// `loadCatalog` (which calls this); tests that want allEntries to
    /// sandbox set the override via `setTestOverrideDirectory` first.
    private static func loadFromDiskRespectingOverride() async -> SampleCodeCatalogJSON? {
        let dir = await testOverride.get() ?? Shared.Constants.defaultSampleCodeDirectory
        return loadFromDisk(at: dir)
    }

    /// Which source the cached catalog was loaded from. Returns nil before
    /// the first `loadCatalog` call.
    public static var loadedSource: Source? {
        get async {
            await cache.get()?.1
        }
    }

    /// Total number of sample code entries
    public static var count: Int {
        get async {
            await loadCatalog().count
        }
    }

    /// Last crawled date
    public static var lastCrawled: String {
        get async {
            await loadCatalog().lastCrawled
        }
    }

    /// Catalog version
    public static var version: String {
        get async {
            await loadCatalog().version
        }
    }

    /// All sample code entries
    public static var allEntries: [SampleCodeEntry] {
        get async {
            await loadCatalog().entries
        }
    }

    /// Get entries for a specific framework
    public static func entries(for framework: String) async -> [SampleCodeEntry] {
        await allEntries.filter { $0.framework.lowercased() == framework.lowercased() }
    }

    /// Search entries by title or description
    public static func search(_ query: String) async -> [SampleCodeEntry] {
        let lowercasedQuery = query.lowercased()
        return await allEntries.filter { entry in
            entry.title.lowercased().contains(lowercasedQuery) ||
                entry.description.lowercased().contains(lowercasedQuery)
        }
    }
}
