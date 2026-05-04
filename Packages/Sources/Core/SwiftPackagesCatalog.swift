// swiftlint:disable identifier_name
// SwiftPackagesCatalog.swift
//
// Seed list of Swift package URLs, slimmed (#161 follow-up) from the original
// 3.4 MB bundled JSON catalog to a compiled-in `[String]` of URLs. Rich
// metadata (stars, description, license, etc.) is no longer part of the
// bundled catalog — once v1.0.0 First Light ships `packages.db` as a
// separately-distributed artifact, that metadata comes from the DB instead.
//
// The catalog retains the `SwiftPackageEntry` shape so existing consumers
// compile unchanged; fields that used to come from the JSON (stars, license,
// description, etc.) now default to `nil` / `0` / `false`.

import Foundation
import Resources

/// One Swift package entry. Originally derived from a rich JSON catalog;
/// after the #161 slimming, most fields default since only the URL is
/// compiled in. Consumers that still need the metadata should fetch from
/// GitHub or read from `packages.db` (v1.0.0+).
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
    public let updatedAt: String?

    public init(
        owner: String,
        repo: String,
        url: String,
        description: String? = nil,
        stars: Int = 0,
        language: String? = nil,
        license: String? = nil,
        fork: Bool = false,
        archived: Bool = false,
        updatedAt: String? = nil
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

    /// Parse a URL into an entry. Handles `https://github.com/<owner>/<repo>`
    /// primarily; also tolerates `.git` suffixes and non-github hosts by
    /// taking the last two path components as owner/repo.
    static func fromURL(_ url: String) -> SwiftPackageEntry? {
        guard let parsed = URL(string: url) else { return nil }
        var path = parsed.path
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[parts.count - 2]
        let repo = parts[parts.count - 1]
        return SwiftPackageEntry(owner: owner, repo: repo, url: url)
    }
}

/// Complete catalog of all Swift packages — URL list only post-#161.
/// Keeps the async-actor-cached shape for API compatibility with existing
/// consumers even though the data is now a compile-time constant.
public enum SwiftPackagesCatalog {
    private actor Cache {
        var entries: [SwiftPackageEntry]?

        func get() -> [SwiftPackageEntry]? {
            entries
        }

        func set(_ newEntries: [SwiftPackageEntry]) {
            entries = newEntries
        }
    }

    private static let cache = Cache()

    private static func loadEntries() async -> [SwiftPackageEntry] {
        if let cached = await cache.get() { return cached }
        let entries = SwiftPackagesCatalogEmbedded.urls.compactMap(SwiftPackageEntry.fromURL)
        await cache.set(entries)
        return entries
    }

    /// Total number of Swift packages in the bundled URL list.
    public static var count: Int {
        get async { await loadEntries().count }
    }

    /// Last crawled date (stamped at catalog generation time).
    public static var lastCrawled: String {
        get async { SwiftPackagesCatalogEmbedded.lastCrawled }
    }

    /// Catalog version marker. Fixed string post-slim; bumped when the URL
    /// schema changes, not on every content refresh.
    public static var version: String {
        get async { "url-only-1" }
    }

    /// Data source description.
    public static var source: String {
        get async { "Bundled URL seed list" }
    }

    /// All Swift package entries (URL-only; metadata fields default).
    public static var allPackages: [SwiftPackageEntry] {
        get async { await loadEntries() }
    }

    /// Packages whose owner matches (case-insensitive).
    public static func packages(by owner: String) async -> [SwiftPackageEntry] {
        await allPackages.filter { $0.owner.lowercased() == owner.lowercased() }
    }

    /// Search packages by repo name (description is nil post-slim).
    public static func search(_ query: String) async -> [SwiftPackageEntry] {
        let q = query.lowercased()
        return await allPackages.filter { $0.repo.lowercased().contains(q) }
    }

    // Removed post-#161: packages(license:), activePackages(minStars:), topPackages(limit:)
    // rely on metadata no longer in the bundled catalog. Use packages.db (v1.0.0+)
    // for metadata-driven queries.
}
