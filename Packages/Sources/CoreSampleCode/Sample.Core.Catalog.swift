// This file loads the Apple Sample Code Library from JSON.
//
// Source of truth: `<sample-code-dir>/catalog.json` written by
// `cupertino fetch --type code` (Apple's `samplecode.json` listing
// transformed to the SampleCodeCatalogJSON shape). The previous
// embedded blob (SampleCodeCatalogEmbedded) was deleted in #215 —
// auto-discovery is the only path now.

import Foundation
import SharedConstants
import SharedCore

/// Represents a sample code project from Apple
extension Sample.Core {
    public struct Entry: Codable, Sendable {
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
}

/// JSON structure for sample code catalog
struct SampleCodeCatalogJSON: Codable {
    let version: String
    let lastCrawled: String
    let count: Int
    let entries: [Sample.Core.Entry]
}

/// Complete catalog of all Apple sample code projects.
///
/// Reads from `<sampleCodeDirectory>/catalog.json` (written by
/// `cupertino fetch --type code`). Returns an empty catalog when no
/// on-disk file exists or it fails to decode — there is no embedded
/// fallback (#215). Callers (e.g. `SearchIndexBuilder`) should check
/// `loadedSource` and warn the user when the catalog is missing so the
/// fix is obvious: run fetch.
///
/// Post-#535: converted from a `static enum` Singleton (process-wide
/// `Cache` + `TestOverride` actors + reach for
/// `Shared.Constants.defaultSampleCodeDirectory` via `BinaryConfig.shared`)
/// to a per-instance actor. Each composition root constructs one with
/// the resolved sample-code directory; tests construct one per test
/// with a `tempDir`. The previous `setTestOverrideDirectory` testing
/// hook is gone — tests just instantiate the actor with the directory
/// they want.
extension Sample.Core {
    public actor Catalog {
        /// File name written by `SampleCodeDownloader` next to the fetched zips
        /// so `cupertino save` can pick up the freshly-discovered metadata.
        public static let onDiskCatalogFilename = "catalog.json"

        /// Source the catalog was loaded from on the most recent `loadCatalog`
        /// call. Useful for telling users via the build log whether their save
        /// is indexing real data or skipping for lack of input.
        public enum Source: String, Sendable {
            /// `<sampleCodeDirectory>/catalog.json` was found and decoded successfully.
            case onDisk
            /// No on-disk catalog (file absent or unparseable). Caller should
            /// hint at running `cupertino fetch --type code` to populate it.
            case missing
        }

        private let sampleCodeDirectory: URL
        private var catalog: SampleCodeCatalogJSON?
        private var source: Source?

        public init(sampleCodeDirectory: URL) {
            self.sampleCodeDirectory = sampleCodeDirectory
        }

        /// Reset the cached catalog. Used by tests to force `loadCatalog` to
        /// re-evaluate disk state between cases.
        public func resetCache() {
            catalog = nil
            source = nil
        }

        /// Load catalog from `<sampleCodeDirectory>/catalog.json`. Returns an
        /// empty catalog if the file is missing or unparseable (#215: no
        /// embedded fallback). The result + source are cached for this
        /// actor's lifetime; call `resetCache` to re-evaluate.
        private func loadCatalog() -> SampleCodeCatalogJSON {
            if let catalog {
                return catalog
            }

            if let onDisk = Self.loadFromDisk(at: sampleCodeDirectory) {
                catalog = onDisk
                source = .onDisk
                return onDisk
            }

            let empty = SampleCodeCatalogJSON(
                version: "missing",
                lastCrawled: "",
                count: 0,
                entries: []
            )
            catalog = empty
            source = .missing
            return empty
        }

        /// Read `<directory>/catalog.json` if present and parseable. Static so
        /// tests can drive disk parsing without constructing an actor.
        /// (`internal` because `SampleCodeCatalogJSON` is internal — exposing
        /// the JSON shape was never part of the public surface.)
        static func loadFromDisk(at directory: URL) -> SampleCodeCatalogJSON? {
            let url = directory.appendingPathComponent(onDiskCatalogFilename)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SampleCodeCatalogJSON.self, from: data)
        }

        /// Test/health-check probe: does `<directory>/catalog.json` exist and
        /// parse? Returns true on success, false otherwise. Public surface
        /// for tests that previously used `loadFromDisk(at:) != nil`.
        public static func hasParseableCatalog(at directory: URL) -> Bool {
            loadFromDisk(at: directory) != nil
        }

        /// Which source the cached catalog was loaded from. Returns nil before
        /// the first `loadCatalog` call.
        public var loadedSource: Source? {
            source
        }

        /// Total number of sample code entries
        public var count: Int {
            loadCatalog().count
        }

        /// Last crawled date
        public var lastCrawled: String {
            loadCatalog().lastCrawled
        }

        /// Catalog version
        public var version: String {
            loadCatalog().version
        }

        /// All sample code entries
        public var allEntries: [Sample.Core.Entry] {
            loadCatalog().entries
        }

        /// Get entries for a specific framework
        public func entries(for framework: String) -> [Sample.Core.Entry] {
            allEntries.filter { $0.framework.lowercased() == framework.lowercased() }
        }

        /// Search entries by title or description
        public func search(_ query: String) -> [Sample.Core.Entry] {
            let lowercasedQuery = query.lowercased()
            return allEntries.filter { entry in
                entry.title.lowercased().contains(lowercasedQuery) ||
                    entry.description.lowercased().contains(lowercasedQuery)
            }
        }
    }
}
