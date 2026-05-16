import Foundation
import SharedConstants

/// Behavioural contract for the search-index database.
///
/// Production implementation: `Search.Index` (the actor in the Search SPM
/// target). Consumers — Services read commands, MCPSupport responders,
/// CLI runners — accept this protocol instead of taking a behavioural
/// dependency on the Search target.
///
/// The protocol surfaces every method Services calls on `Search.Index`:
/// `search`, `getDocumentContent`, `listFrameworks`, `documentCount`,
/// and `disconnect`. The full-parameter `search` lives on the protocol
/// itself; a convenience overload with `nil`-defaulted platform filters
/// is provided as a protocol extension so existing call sites with
/// fewer arguments compile unchanged.
extension Search {
    public protocol Database: Sendable {
        /// Run a full search across the index.
        ///
        /// - Parameters:
        ///   - query: Free-text query (FTS5 syntax).
        ///   - source: Filter by source prefix (`apple-docs`, `samples`, …).
        ///   - framework: Filter by framework slug.
        ///   - language: Filter by primary language (`swift`, `objc`, `c`).
        ///   - limit: Maximum number of results.
        ///   - includeArchive: Include archive results when `source` is nil.
        ///   - minIOS / minMacOS / minTvOS / minWatchOS / minVisionOS:
        ///     Filter rows whose minimum-version annotation falls below the
        ///     dotted-decimal threshold. Pass `nil` to skip a platform.
        func search(
            query: String,
            source: String?,
            framework: String?,
            language: String?,
            limit: Int,
            includeArchive: Bool,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?
        ) async throws -> [Search.Result]

        /// Fetch the pre-rendered document content for a URI.
        ///
        /// Returns `nil` when the URI is not present in the index. Throws
        /// only on real database failures.
        func getDocumentContent(uri: String, format: Search.DocumentFormat) async throws -> String?

        /// All frameworks present in the index with their document counts.
        func listFrameworks() async throws -> [String: Int]

        /// Total document count across every source in the index.
        func documentCount() async throws -> Int

        /// Close the database connection. Idempotent; safe to call from a
        /// `defer` even when the actor has already shut down.
        func disconnect() async

        // MARK: - Semantic Symbol Search (#81)

        /// Semantic search across AST-extracted symbols by name pattern + kind.
        func searchSymbols(
            query: String?,
            kind: String?,
            isAsync: Bool?,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult]

        /// Semantic search for property-wrapper attributes (e.g. `@Observable`,
        /// `@State`, `@MainActor`).
        func searchPropertyWrappers(
            wrapper: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult]

        /// Semantic search for Swift concurrency patterns
        /// (`async`, `actor`, `sendable`, `mainactor`, `task`, `asyncsequence`).
        func searchConcurrencyPatterns(
            pattern: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult]

        /// Semantic search for types by protocol conformance.
        func searchConformances(
            protocolName: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult]

        /// Semantic search by generic-parameter constraint (#665, #409 Layer 2).
        ///
        /// Matches the AST-extracted `doc_symbols.generic_params` column
        /// as a substring (so `Sendable` returns both `T: Sendable` and
        /// `T: Hashable & Sendable`). Results carry the matched
        /// generic-parameter clause on `SymbolSearchResult.genericParams`
        /// so the MCP layer can echo what matched.
        func searchByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult]

        // MARK: - Class inheritance (#274)

        /// Resolve a user-supplied symbol name to one or more apple-docs URIs.
        /// Multiple candidates means the title is ambiguous across
        /// frameworks (`Color` in SwiftUI + AppKit) — caller surfaces
        /// disambiguation. Empty when no apple-docs row carries the title.
        func resolveSymbolURIs(title: String) async throws -> [Search.InheritanceCandidate]

        /// Walk the class-inheritance graph from `startURI` in the given
        /// direction up to `maxDepth` hops. Tree shape is BFS-frontier
        /// (one level at a time before recursing).
        func walkInheritance(
            startURI: String,
            direction: Search.InheritanceDirection,
            maxDepth: Int
        ) async throws -> Search.InheritanceTree

        // MARK: - #226 — platform-availability batch lookup

        /// Batch-fetch `min_*` platform availability for a list of URIs
        /// in one round-trip. Used by `CompositeToolProvider`'s
        /// search-style tool handlers to apply the MCP `--platform` /
        /// `--min-version` filter post-fetch when the per-result
        /// `SymbolSearchResult` doesn't carry version data on its own.
        ///
        /// Returns a `[uri → PlatformMinima]` map. URIs absent from the
        /// map have no `docs_metadata` row (treat as "no platform info;
        /// reject when any filter is set" — same IS-NOT-NULL semantics
        /// as the unified `search` tool).
        func fetchPlatformMinima(
            uris: [String]
        ) async throws -> [String: Search.PlatformMinima]
    }

    /// #226 — `[uri → minimum platform versions]` value returned by
    /// `Database.fetchPlatformMinima(uris:)`. Distinct from the
    /// pre-existing `Search.PlatformAvailability` (which is a per-platform
    /// availability record — name, introducedAt, deprecated, beta —
    /// embedded in `Search.Result.availability`). `PlatformMinima` is
    /// the flat 5-field shape used by the MCP search-style platform
    /// filter (`minIOS` / `minMacOS` / etc.), one record per URI.
    ///
    /// Lives in `SearchModels` (not `Search`) because the `Database`
    /// protocol references it across the package seam — `CompositeToolProvider`
    /// consumes the protocol without importing the `Search` SPM target.
    /// Pure value type; semver-format strings (`"17.0"`, `"10.13"`).
    /// #226 — predicate used by `CompositeToolProvider`'s search-style
    /// tool handlers to filter result rows by the MCP `--platform` /
    /// `--min-version` args. Lives in `SearchModels` (not `Search`)
    /// because the caller doesn't import the Search SPM target.
    ///
    /// Semantics: a row passes when *every set filter* is `>=` the row's
    /// own minimum (semver-aware — `"10.13" <= "10.2"` is **false**).
    /// A row with no platform info is rejected when any filter is set
    /// (matches the unified `search` tool's IS-NOT-NULL pre-gate at
    /// `Search.Index.Search.swift:166-180`).
    public enum PlatformFilter {
        public static func passes(
            minima: PlatformMinima?,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?
        ) -> Bool {
            let fIOS = (minIOS?.isEmpty == true) ? nil : minIOS
            let fMac = (minMacOS?.isEmpty == true) ? nil : minMacOS
            let fTv = (minTvOS?.isEmpty == true) ? nil : minTvOS
            let fWatch = (minWatchOS?.isEmpty == true) ? nil : minWatchOS
            let fVision = (minVisionOS?.isEmpty == true) ? nil : minVisionOS
            if fIOS == nil, fMac == nil, fTv == nil, fWatch == nil, fVision == nil { return true }
            guard let minima else { return false }
            if let f = fIOS, let rv = minima.minIOS, !isVersion(rv, lessThanOrEqualTo: f) { return false }
            if let f = fIOS, minima.minIOS == nil { return false }
            if let f = fMac, let rv = minima.minMacOS, !isVersion(rv, lessThanOrEqualTo: f) { return false }
            if let f = fMac, minima.minMacOS == nil { return false }
            if let f = fTv, let rv = minima.minTvOS, !isVersion(rv, lessThanOrEqualTo: f) { return false }
            if let f = fTv, minima.minTvOS == nil { return false }
            if let f = fWatch, let rv = minima.minWatchOS, !isVersion(rv, lessThanOrEqualTo: f) { return false }
            if let f = fWatch, minima.minWatchOS == nil { return false }
            if let f = fVision, let rv = minima.minVisionOS, !isVersion(rv, lessThanOrEqualTo: f) { return false }
            if let f = fVision, minima.minVisionOS == nil { return false }
            return true
        }

        /// Semver-correct `lhs <= rhs` (string compare gets `"10.13" <= "10.2"` wrong).
        /// Identical algorithm to `Search.Index.isVersion`; duplicated here as `public`
        /// so consumers outside the Search SPM target can use the same predicate.
        public static func isVersion(_ lhs: String, lessThanOrEqualTo rhs: String) -> Bool {
            let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
            let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }
            for idx in 0..<max(lhsComponents.count, rhsComponents.count) {
                let lhsValue = idx < lhsComponents.count ? lhsComponents[idx] : 0
                let rhsValue = idx < rhsComponents.count ? rhsComponents[idx] : 0
                if lhsValue < rhsValue { return true }
                if lhsValue > rhsValue { return false }
            }
            return true
        }
    }

    public struct PlatformMinima: Sendable, Equatable {
        public let minIOS: String?
        public let minMacOS: String?
        public let minTvOS: String?
        public let minWatchOS: String?
        public let minVisionOS: String?

        public init(
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) {
            self.minIOS = minIOS
            self.minMacOS = minMacOS
            self.minTvOS = minTvOS
            self.minWatchOS = minWatchOS
            self.minVisionOS = minVisionOS
        }
    }
}

// MARK: - Convenience overload with defaulted platform filters

extension Search.Database {
    /// Convenience overload that defaults every platform-availability
    /// filter to `nil`. Callers who don't restrict by minimum OS version
    /// stay one line.
    public func search(
        query: String,
        source: String? = nil,
        framework: String? = nil,
        language: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit,
        includeArchive: Bool = false
    ) async throws -> [Search.Result] {
        try await search(
            query: query,
            source: source,
            framework: framework,
            language: language,
            limit: limit,
            includeArchive: includeArchive,
            minIOS: nil,
            minMacOS: nil,
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil
        )
    }
}
