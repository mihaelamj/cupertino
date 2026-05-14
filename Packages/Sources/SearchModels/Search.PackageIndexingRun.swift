import Foundation

// MARK: - Search.PackageIndexingRun

/// Closure shape for running a complete `packages.db` indexing pass:
/// open the index, walk the on-disk package tree, write every package
/// row, summarise the resulting database, and disconnect.
///
/// `Indexer.PackagesService` accepts one of these instead of reaching
/// directly into `Search.PackageIndex` + `Search.PackageIndexer`, so
/// the Indexer SPM target keeps its dependency graph free of the
/// concrete Search-target actors. The composition root (the CLI's
/// `save` command) supplies the closure with the standard
/// `Search.PackageIndex` + `Search.PackageIndexer` wiring.
///
/// Mirrors the `MakeSearchDatabase` / `MarkdownToStructuredPage` /
/// `SampleCatalogFetch` closure-typealias pattern already in
/// SearchModels: the abstraction lives in this value-types target,
/// the implementation lives in the producer target, the wiring lives
/// at the composition root.
public extension Search {
    typealias PackageIndexingRun = @Sendable (
        _ packagesRoot: URL,
        _ packagesDBPath: URL,
        _ onProgress: @escaping @Sendable (String, Int, Int) -> Void
    ) async throws -> PackageIndexingOutcome
}

// MARK: - Search.PackageIndexingOutcome

/// Statistics emitted by a `Search.PackageIndexingRun` closure.
///
/// The Indexer translates this into its public
/// `Indexer.PackagesService.Outcome` event payload (which keeps the
/// same eight numeric fields).
public extension Search {
    struct PackageIndexingOutcome: Sendable {
        public let packagesIndexed: Int
        public let packagesFailed: Int
        public let totalFiles: Int
        public let totalBytes: Int64
        public let durationSeconds: Double
        public let totalPackagesInDB: Int
        public let totalFilesInDB: Int
        public let totalBytesInDB: Int64

        public init(
            packagesIndexed: Int,
            packagesFailed: Int,
            totalFiles: Int,
            totalBytes: Int64,
            durationSeconds: Double,
            totalPackagesInDB: Int,
            totalFilesInDB: Int,
            totalBytesInDB: Int64
        ) {
            self.packagesIndexed = packagesIndexed
            self.packagesFailed = packagesFailed
            self.totalFiles = totalFiles
            self.totalBytes = totalBytes
            self.durationSeconds = durationSeconds
            self.totalPackagesInDB = totalPackagesInDB
            self.totalFilesInDB = totalFilesInDB
            self.totalBytesInDB = totalBytesInDB
        }
    }
}
