import Foundation

// MARK: - Search.PackagesSearcher

extension Search {
    /// Read-only seam for the packages-database half of the smart-query
    /// fan-out. Captures the surface that the Services and MCP layers
    /// need against `packages.db`, so callers don't take a behavioural
    /// dependency on the Search target's BM25 + intent + chunk-extraction
    /// internals (`Search.PackageQuery`).
    ///
    /// Production conformer: `Search.PackageQuery` in the Search target.
    /// Tests pass an in-memory stub.
    ///
    /// Filed against `#789`-style architectural gap discovered during the
    /// v1.2.0 read-side wiring round: pre-PR-2, both
    /// `Services.UnifiedSearchService.searchAll` and
    /// `CompositeToolProvider.handleSearchDocs` routed the `packages`
    /// source through `Search.Database.search`, which only knows the six
    /// search.db source values (apple-docs, apple-archive, hig,
    /// swift-evolution, swift-org, swift-book). The `packages` async-let
    /// on `searchAll` therefore returned empty for every query, and the
    /// single-source MCP path silently returned the same. This seam fixes
    /// both call sites by giving them a typed handle to packages.db.
    public protocol PackagesSearcher: Sendable {
        /// Search `packages.db` for the given natural-language question.
        ///
        /// - Parameters:
        ///   - query: free-text question, classified into an intent +
        ///     column-weighted BM25 query downstream.
        ///   - limit: per-source result cap. Fewer rows is fine, more is
        ///     a contract violation.
        ///   - availability: optional `--platform` / `--min-version`
        ///     pushdown; AND-combined with the query at SQL time.
        ///   - swiftTools: optional `--swift-tools` deployment-target
        ///     pushdown; orthogonal to `availability`.
        ///   - appleImport: optional Apple-framework module name
        ///     (`SwiftUI`, `Combine`, …). When set, restricts candidates
        ///     to packages whose `package_metadata.apple_imports_json`
        ///     contains the module via a quote-bracketed JSON LIKE.
        ///
        /// - Returns: `[Search.Result]` shaped for the unified formatter:
        ///   - `source` = "packages"
        ///   - `uri`    = "packages://<owner>/<repo>/<relpath>"
        ///   - `title`  = file title
        ///   - `summary` = chunk extract
        ///   - `rank`   = negative score so lower-is-better matches the
        ///                docs-side convention.
        func searchPackages(
            query: String,
            limit: Int,
            availability: Search.AvailabilityFilter?,
            swiftTools: Search.SwiftToolsFilter?,
            appleImport: String?
        ) async throws -> [Search.Result]

        /// Search `packages.db` for symbols whose generic constraints,
        /// signature, or name match the given constraint token. Used by
        /// the MCP `search_generics` tool's cross-DB fan-out (`#857`).
        ///
        /// - Parameters:
        ///   - constraint: a token like `View`, `Equatable`, `Sendable`.
        ///   - framework: optional module-name filter applied against
        ///     `package_symbols.module` when non-nil.
        ///   - limit: row cap.
        ///
        /// - Returns: `[Search.Result]` shaped the same way as
        ///   `searchPackages` so the cross-DB merge in
        ///   `CompositeToolProvider.handleSearchGenerics` can union the
        ///   three sources into a single ranked list.
        func searchPackageSymbolsByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.Result]
    }
}
