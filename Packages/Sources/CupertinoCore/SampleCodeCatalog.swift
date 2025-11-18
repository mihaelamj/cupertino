// This file loads the Apple Sample Code Library from JSON
// Last updated: 2025-11-17
// JSON file: CupertinoResources/sample-code-catalog.json

import CupertinoResources
import Foundation

/// Represents a sample code project from Apple
public struct SampleCodeEntry: Codable, Sendable {
    public let title: String
    public let url: String
    public let framework: String
    public let description: String
    public let zipFilename: String
    public let webURL: String

    public init(title: String, url: String, framework: String, description: String, zipFilename: String, webURL: String) {
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

/// Complete catalog of all Apple sample code projects
public enum SampleCodeCatalog {
    /// Cached catalog data (thread-safe via actor isolation)
    private actor Cache {
        var catalog: SampleCodeCatalogJSON?

        func get() -> SampleCodeCatalogJSON? {
            catalog
        }

        func set(_ newCatalog: SampleCodeCatalogJSON) {
            catalog = newCatalog
        }
    }

    private static let cache = Cache()

    /// Load catalog from JSON resource
    private static func loadCatalog() async -> SampleCodeCatalogJSON {
        if let cached = await cache.get() {
            return cached
        }

        guard let url = CupertinoResources.bundle.url(forResource: "sample-code-catalog", withExtension: "json") else {
            fatalError("❌ sample-code-catalog.json not found in Resources")
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let catalog = try decoder.decode(SampleCodeCatalogJSON.self, from: data)
            await cache.set(catalog)
            return catalog
        } catch {
            fatalError("❌ Failed to load sample-code-catalog.json: \(error)")
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
