// This file loads the Priority Packages catalog from JSON
// Last updated: 2025-11-17
// JSON file: CupertinoResources/priority-packages.json

import CupertinoResources
import Foundation

/// Represents a priority package entry
public struct PriorityPackage: Codable, Sendable {
    public let owner: String?
    public let repo: String
    public let url: String

    public init(owner: String? = nil, repo: String, url: String) {
        self.owner = owner
        self.repo = repo
        self.url = url
    }
}

/// Tier information for priority packages
public struct PriorityTier: Codable, Sendable {
    public let description: String
    public let owner: String?
    public let count: Int
    public let packages: [PriorityPackage]

    public init(description: String, owner: String? = nil, count: Int, packages: [PriorityPackage]) {
        self.description = description
        self.owner = owner
        self.count = count
        self.packages = packages
    }
}

/// Tiers structure
public struct PriorityTiers: Codable, Sendable {
    public let appleOfficial: PriorityTier
    public let ecosystem: PriorityTier

    enum CodingKeys: String, CodingKey {
        case appleOfficial = "apple_official"
        case ecosystem
    }
}

/// Statistics for priority packages
public struct PriorityPackageStats: Codable, Sendable {
    public let totalCriticalApplePackages: Int
    public let totalEcosystemPackages: Int
    public let totalPriorityPackages: Int
}

/// JSON structure for priority packages catalog
struct PriorityPackagesCatalogJSON: Codable {
    let version: String
    let lastUpdated: String
    let description: String
    let tiers: PriorityTiers
    let stats: PriorityPackageStats
}

/// Complete catalog of curated high-priority Swift packages
public enum PriorityPackagesCatalog {
    /// Cached catalog data (thread-safe via actor isolation)
    private actor Cache {
        var catalog: PriorityPackagesCatalogJSON?

        func get() -> PriorityPackagesCatalogJSON? {
            catalog
        }

        func set(_ newCatalog: PriorityPackagesCatalogJSON) {
            catalog = newCatalog
        }
    }

    private static let cache = Cache()

    /// Load catalog from JSON resource
    private static func loadCatalog() async -> PriorityPackagesCatalogJSON {
        if let cached = await cache.get() {
            return cached
        }

        guard let url = CupertinoResources.bundle.url(forResource: "priority-packages", withExtension: "json") else {
            fatalError("❌ priority-packages.json not found in Resources")
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let catalog = try decoder.decode(PriorityPackagesCatalogJSON.self, from: data)
            await cache.set(catalog)
            return catalog
        } catch {
            fatalError("❌ Failed to load priority-packages.json: \(error)")
        }
    }

    /// Catalog version
    public static var version: String {
        get async {
            await loadCatalog().version
        }
    }

    /// Last updated date
    public static var lastUpdated: String {
        get async {
            await loadCatalog().lastUpdated
        }
    }

    /// Catalog description
    public static var description: String {
        get async {
            await loadCatalog().description
        }
    }

    /// All tiers
    public static var tiers: PriorityTiers {
        get async {
            await loadCatalog().tiers
        }
    }

    /// Statistics
    public static var stats: PriorityPackageStats {
        get async {
            await loadCatalog().stats
        }
    }

    /// All Apple official packages
    public static var applePackages: [PriorityPackage] {
        get async {
            await loadCatalog().tiers.appleOfficial.packages
        }
    }

    /// All ecosystem packages
    public static var ecosystemPackages: [PriorityPackage] {
        get async {
            await loadCatalog().tiers.ecosystem.packages
        }
    }

    /// All priority packages (combined)
    public static var allPackages: [PriorityPackage] {
        get async {
            let catalog = await loadCatalog()
            return catalog.tiers.appleOfficial.packages + catalog.tiers.ecosystem.packages
        }
    }

    /// Check if a package is in the priority list
    public static func isPriority(owner: String, repo: String) async -> Bool {
        let all = await allPackages
        return all.contains { pkg in
            let pkgOwner = pkg.owner ?? "apple"
            return pkgOwner.lowercased() == owner.lowercased() && pkg.repo.lowercased() == repo.lowercased()
        }
    }

    /// Get priority package by repo name (searches all tiers)
    public static func package(named repo: String) async -> PriorityPackage? {
        let all = await allPackages
        return all.first { $0.repo.lowercased() == repo.lowercased() }
    }
}
