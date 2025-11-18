// This file loads the Swift Packages Library from JSON
// Last updated: 2025-11-17
// JSON file: CupertinoResources/swift-packages-catalog.json
// Source: Swift Package Index + GitHub API

import Foundation
import Resources

/// Represents a Swift package from the Swift Package Index + GitHub
public struct SwiftPackageEntry: Codable, Sendable {
    public let owner: String
    public let repo: String
    public let url: String
    public let description: String?
    public let stars: Int
    public let language: String?
    public let license: String?
    public let fork: Bool
    public let archived: Bool
    public let updatedAt: String

    public init(
        owner: String,
        repo: String,
        url: String,
        description: String?,
        stars: Int,
        language: String?,
        license: String?,
        fork: Bool,
        archived: Bool,
        updatedAt: String
    ) {
        self.owner = owner
        self.repo = repo
        self.url = url
        self.description = description
        self.stars = stars
        self.language = language
        self.license = license
        self.fork = fork
        self.archived = archived
        self.updatedAt = updatedAt
    }
}

/// JSON structure for Swift packages catalog
struct SwiftPackagesCatalogJSON: Codable {
    let version: String
    let lastCrawled: String
    let source: String
    let count: Int
    let packages: [SwiftPackageEntry]
}

/// Complete catalog of all Swift packages from Swift Package Index + GitHub
public enum SwiftPackagesCatalog {
    /// Cached catalog data (thread-safe via actor isolation)
    private actor Cache {
        var catalog: SwiftPackagesCatalogJSON?

        func get() -> SwiftPackagesCatalogJSON? {
            catalog
        }

        func set(_ newCatalog: SwiftPackagesCatalogJSON) {
            catalog = newCatalog
        }
    }

    private static let cache = Cache()

    /// Load catalog from JSON resource
    private static func loadCatalog() async -> SwiftPackagesCatalogJSON {
        if let cached = await cache.get() {
            return cached
        }

        guard let url = CupertinoResources.bundle.url(forResource: "swift-packages-catalog", withExtension: "json")
        else {
            fatalError("❌ swift-packages-catalog.json not found in Resources")
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let catalog = try decoder.decode(SwiftPackagesCatalogJSON.self, from: data)
            await cache.set(catalog)
            return catalog
        } catch {
            fatalError("❌ Failed to load swift-packages-catalog.json: \(error)")
        }
    }

    /// Total number of Swift packages
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

    /// Data source description
    public static var source: String {
        get async {
            await loadCatalog().source
        }
    }

    /// All Swift package entries
    public static var allPackages: [SwiftPackageEntry] {
        get async {
            await loadCatalog().packages
        }
    }

    /// Get packages by owner
    public static func packages(by owner: String) async -> [SwiftPackageEntry] {
        await allPackages.filter { $0.owner.lowercased() == owner.lowercased() }
    }

    /// Search packages by repo name or description
    public static func search(_ query: String) async -> [SwiftPackageEntry] {
        let lowercasedQuery = query.lowercased()
        return await allPackages.filter { package in
            package.repo.lowercased().contains(lowercasedQuery) ||
                (package.description?.lowercased().contains(lowercasedQuery) ?? false)
        }
    }

    /// Get packages by license
    public static func packages(license: String) async -> [SwiftPackageEntry] {
        await allPackages.filter { $0.license?.lowercased() == license.lowercased() }
    }

    /// Get non-fork, non-archived packages with minimum stars
    public static func activePackages(minStars: Int = 0) async -> [SwiftPackageEntry] {
        await allPackages.filter { !$0.fork && !$0.archived && $0.stars >= minStars }
    }

    /// Get top packages by stars
    public static func topPackages(limit: Int = 100) async -> [SwiftPackageEntry] {
        await Array(allPackages.sorted { $0.stars > $1.stars }.prefix(limit))
    }
}
