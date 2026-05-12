// This file loads the Priority Packages catalog from JSON
// Supports user-selected packages from ~/.cupertino/selected-packages.json
// Falls back to bundled priority-packages.json if user file doesn't exist

import Foundation
import Resources
import SharedCore
import SharedConstants

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

/// Tiers structure (apple_official is optional to support TUI-generated files)
public struct PriorityTiers: Codable, Sendable {
    public let appleOfficial: PriorityTier?
    public let ecosystem: PriorityTier

    enum CodingKeys: String, CodingKey {
        case appleOfficial = "apple_official"
        case ecosystem
    }
}

/// Statistics for priority packages (some fields optional to support TUI-generated files)
public struct PriorityPackageStats: Codable, Sendable {
    public let totalCriticalApplePackages: Int?
    public let totalEcosystemPackages: Int?
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
    /// User-writable location for selected packages: ~/.cupertino/selected-packages.json
    private static var userSelectionsURL: URL {
        Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(Shared.Constants.FileName.selectedPackages)
    }

    /// Cached catalog data (thread-safe via actor isolation)
    private actor Cache {
        var catalog: PriorityPackagesCatalogJSON?
        var useBundledOnly = false

        func get() -> PriorityPackagesCatalogJSON? {
            catalog
        }

        func set(_ newCatalog: PriorityPackagesCatalogJSON) {
            catalog = newCatalog
        }

        func clear() {
            catalog = nil
        }

        func setUseBundledOnly(_ value: Bool) {
            useBundledOnly = value
            catalog = nil // Clear cache when changing mode
        }

        func shouldSkipUserFile() -> Bool {
            useBundledOnly
        }
    }

    private static let cache = Cache()

    /// Clear the cache (useful when user file changes)
    public static func clearCache() async {
        await cache.clear()
    }

    /// Force using bundled file only (for testing)
    /// Call with `true` before tests, `false` after to restore normal behavior
    public static func setUseBundledOnly(_ bundledOnly: Bool) async {
        await cache.setUseBundledOnly(bundledOnly)
    }

    /// Load catalog - checks user file first, falls back to bundled resource
    private static func loadCatalog() async -> PriorityPackagesCatalogJSON {
        if let cached = await cache.get() {
            return cached
        }

        // Try user selections file first (unless testing with bundled only)
        let skipUserFile = await cache.shouldSkipUserFile()
        if !skipUserFile {
            ensureUserSelectionsFileExists()
            if let userCatalog = loadUserCatalog() {
                await cache.set(userCatalog)
                return userCatalog
            }
        }

        // Fall back to embedded resource (#161: no more runtime bundle lookup)
        guard let data = CupertinoResources.jsonData(named: "priority-packages") else {
            fatalError("❌ priority-packages embedded JSON missing — should be impossible")
        }

        do {
            let catalog = try JSONDecoder().decode(PriorityPackagesCatalogJSON.self, from: data)
            await cache.set(catalog)
            return catalog
        } catch {
            fatalError("❌ Failed to decode embedded priority-packages JSON: \(error)")
        }
    }

    /// Load catalog from user selections file if it exists
    private static func loadUserCatalog() -> PriorityPackagesCatalogJSON? {
        let fileURL = userSelectionsURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PriorityPackagesCatalogJSON.self, from: data)
        } catch {
            // User file exists but is invalid - fall back to bundled
            return nil
        }
    }

    /// Ensure user selections file is present and up-to-date.
    ///
    /// On first run: copies the embedded catalog wholesale as the initial
    /// selection. On subsequent runs: additive merge — entries present in
    /// the embedded list but missing from the user file (matched on
    /// `owner.lowercased()/repo.lowercased()`) are appended. User deletions
    /// stick (we never remove), but newly-shipped seeds in
    /// `PriorityPackagesEmbedded.swift` propagate into existing installs the
    /// next time any caller touches `PriorityPackagesCatalog`.
    ///
    /// Fixes the 2026-05-03 staleness bug filed under #218: a Dec 2025
    /// `~/.cupertino/selected-packages.json` was frozen at the priority list
    /// from then, so April 2026 additions (e.g. `mihaelamj/*` packages)
    /// never reached the resolver despite being in the embedded JSON.
    private static func ensureUserSelectionsFileExists() {
        let selectedURL = userSelectionsURL

        guard let embeddedData = CupertinoResources.jsonData(named: "priority-packages") else {
            return
        }

        if !FileManager.default.fileExists(atPath: selectedURL.path) {
            do {
                let baseDir = Shared.Constants.defaultBaseDirectory
                if !FileManager.default.fileExists(atPath: baseDir.path) {
                    try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
                }
                try embeddedData.write(to: selectedURL)
            } catch {
                // Silently fail - fall back to embedded resource in loadCatalog
            }
            return
        }

        // File exists — additively merge any new embedded entries (#218).
        mergeNewEmbeddedEntries(into: selectedURL, from: embeddedData)
    }

    /// Append entries present in `embeddedData` but missing from the user
    /// file at `selectedURL`. Matched on
    /// `owner.lowercased()/repo.lowercased()`. Idempotent — silent when the
    /// user file already covers every embedded entry; prints a one-line
    /// summary when it adds anything. Never removes entries.
    /// `internal` (not `private`) so #218 unit tests can drive it without
    /// touching real disk or network state.
    static func mergeNewEmbeddedEntries(into selectedURL: URL, from embeddedData: Data) {
        let decoder = JSONDecoder()
        guard let embedded = try? decoder.decode(PriorityPackagesCatalogJSON.self, from: embeddedData),
              let userData = try? Data(contentsOf: selectedURL),
              let user = try? decoder.decode(PriorityPackagesCatalogJSON.self, from: userData)
        else {
            return
        }

        func key(_ pkg: PriorityPackage) -> String {
            let derivedOwner: String
            if let owner = pkg.owner, !owner.isEmpty {
                derivedOwner = owner.lowercased()
            } else {
                let parsed = URL(string: pkg.url)?
                    .pathComponents
                    .dropFirst()
                    .first?
                    .lowercased()
                derivedOwner = parsed ?? ""
            }
            return "\(derivedOwner)/\(pkg.repo.lowercased())"
        }

        var userKeys = Set<String>()
        if let apple = user.tiers.appleOfficial {
            for pkg in apple.packages {
                userKeys.insert(key(pkg))
            }
        }
        for pkg in user.tiers.ecosystem.packages {
            userKeys.insert(key(pkg))
        }

        var newApple: [PriorityPackage] = []
        if let apple = embedded.tiers.appleOfficial {
            newApple = apple.packages.filter { !userKeys.contains(key($0)) }
        }
        let newEcosystem = embedded.tiers.ecosystem.packages.filter { !userKeys.contains(key($0)) }

        let totalNew = newApple.count + newEcosystem.count
        guard totalNew > 0 else { return }

        let mergedAppleTier: PriorityTier?
        if let userApple = user.tiers.appleOfficial {
            let merged = userApple.packages + newApple
            mergedAppleTier = PriorityTier(
                description: userApple.description,
                owner: userApple.owner,
                count: merged.count,
                packages: merged
            )
        } else {
            mergedAppleTier = embedded.tiers.appleOfficial
        }

        let userEcosystem = user.tiers.ecosystem
        let mergedEcosystemPackages = userEcosystem.packages + newEcosystem
        let mergedEcosystemTier = PriorityTier(
            description: userEcosystem.description,
            owner: userEcosystem.owner,
            count: mergedEcosystemPackages.count,
            packages: mergedEcosystemPackages
        )

        let mergedTiers = PriorityTiers(
            appleOfficial: mergedAppleTier,
            ecosystem: mergedEcosystemTier
        )

        let totalApple = mergedAppleTier?.packages.count ?? 0
        let totalEco = mergedEcosystemTier.packages.count
        let mergedStats = PriorityPackageStats(
            totalCriticalApplePackages: totalApple,
            totalEcosystemPackages: totalEco,
            totalPriorityPackages: totalApple + totalEco
        )

        let merged = PriorityPackagesCatalogJSON(
            version: embedded.version,
            lastUpdated: embedded.lastUpdated,
            description: user.description,
            tiers: mergedTiers,
            stats: mergedStats
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let mergedData = try? encoder.encode(merged) else {
            return
        }

        do {
            try mergedData.write(to: selectedURL)
            print("📥 selected-packages.json: added \(totalNew) new priority entries from embedded list (#218)")
        } catch {
            // Silently fail - we already have the user file from before
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
            await loadCatalog().tiers.appleOfficial?.packages ?? []
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
            let applePackages = catalog.tiers.appleOfficial?.packages ?? []
            return applePackages + catalog.tiers.ecosystem.packages
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
