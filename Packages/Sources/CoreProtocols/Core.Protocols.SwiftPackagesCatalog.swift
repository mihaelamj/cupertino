// Core.Protocols.SwiftPackagesCatalog.swift
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
extension Core.Protocols {
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
}

/// Complete catalog of all Swift packages — URL list only post-#161.
/// Keeps the async-actor-cached shape for API compatibility with existing
/// consumers even though the data is now a compile-time constant.
extension Core.Protocols {
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
            // #194 — the 568 KB embedded URL list was deleted post-v1.0.x;
            // the canonical Swift-packages corpus now lives in
            // `packages.db` (downloaded via `cupertino setup`). This
            // accessor returns an empty array so legacy callers compile
            // unchanged but read no data:
            //
            // * `Search.Strategies.SwiftPackages` hits its existing
            //   `guard !packages.isEmpty` clean-skip path (#671), so
            //   `cupertino save --packages` cleanly skips with reason
            //   "catalog empty" — the indexer-side rebuild of
            //   `search.db`'s swift-packages source is deferred to a
            //   follow-up PR that rewires it to read from packages.db.
            //
            // * `TUI/PackageCurator` sees an empty package list; the
            //   #194 PR adds a "run `cupertino setup` first" banner so
            //   the empty state is explained, not mysterious.
            //
            // End-user impact: zero. Brew users get the swift-packages
            // search rows from the pre-built `search.db` shipped via
            // `cupertino setup`; they never ran `save --packages`.
            // Bundle size drops by ~530 KB.
            []
        }

        /// Total number of Swift packages in the bundled URL list.
        /// Post-#194: always 0 — see `loadEntries` for the migration
        /// to `packages.db`.
        public static var count: Int {
            get async { 0 }
        }

        /// Last crawled date. Post-#194 the embedded URL list is gone;
        /// returns an empty string. Callers wanting "when did Apple
        /// docs / packages last refresh" should use the per-source
        /// metadata in `packages.db` or `cupertino doctor --freshness`.
        public static var lastCrawled: String {
            get async { "" }
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
            let needle = query.lowercased()
            return await allPackages.filter { $0.repo.lowercased().contains(needle) }
        }

        // Removed post-#161: packages(license:), activePackages(minStars:), topPackages(limit:)
        // rely on metadata no longer in the bundled catalog. Use packages.db (v1.0.0+)
        // for metadata-driven queries.
    }
}
