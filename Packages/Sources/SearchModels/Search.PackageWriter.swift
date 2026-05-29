import Foundation

// MARK: - Search.PackageWriter

/// Write-side seam for the packages.db actor (`Search.PackageIndex` in
/// the SearchSQLite target). Mirrors the read-side `Search.PackagesSearcher`
/// protocol and the `Search.IndexWriter` shape from #896.
///
/// The two write methods cover the postprocessor pipeline's package
/// enrichment surface: `applyAppleStaticConstraints` for the
/// `package_symbols.generic_constraints` enrichment (`#837` stage 2)
/// and `applyAppleImports` for the `package_metadata.apple_imports_json`
/// enrichment (#837 stage 1). The two
/// `Enrichment.Packages*Pass` types in the postprocessor pipeline take
/// `any Search.PackageWriter` so they can stay in the foundation-typed
/// `Enrichment` target without depending on the SQLite-backed concrete.
extension Search {
    public protocol PackageWriter: Sendable {
        /// Apply the authoritative Apple-type static-constraints lookup
        /// to the packages.db `package_symbols.generic_constraints`
        /// column. Idempotent; stamps `enrichment_version` on each
        /// updated row. Returns the affected-row count; nil `lookup`
        /// short-circuits to 0 without touching the DB.
        func applyAppleStaticConstraints(
            lookup: (any Search.StaticConstraintsLookup)?,
            enrichmentVersion: Int
        ) async throws -> Int

        /// Apply the authoritative Apple SDK conformance table to the
        /// packages.db `package_symbols.conformances` column, matched by
        /// symbol name. Idempotent; stamps `enrichment_version`. Used by
        /// `Enrichment.PackagesAppleConformancesPass`. nil `lookup`
        /// short-circuits to 0.
        func applyAppleStaticConformances(
            lookup: (any Search.StaticConformancesLookup)?,
            enrichmentVersion: Int
        ) async throws -> Int

        /// Apply the authoritative Apple-imports lookup to the
        /// packages.db `package_metadata.apple_imports_json` column.
        /// Idempotent; stamps `enrichment_version` on each updated
        /// row. Returns the affected-row count; nil `lookup`
        /// short-circuits to 0 without touching the DB.
        func applyAppleImports(
            lookup: (any Search.StaticConstraintsLookup)?,
            enrichmentVersion: Int
        ) async throws -> Int
    }
}

extension Search.PackageWriter {
    /// Default: no-op. Only the SQLite-backed package index overrides this;
    /// test fakes and other conformers need not implement it.
    public func applyAppleStaticConformances(
        lookup: (any Search.StaticConformancesLookup)?,
        enrichmentVersion _: Int
    ) async throws -> Int {
        _ = lookup
        return 0
    }
}
