import Foundation

// MARK: - Search.PackageIndexing.Runner

/// Sub-namespace grouping the PackageIndexing-related types (Runner +
/// Outcome). Post-#1042 type-name deepening; back-compat typealiases
/// preserve `Search.PackageIndexingRunner` / `Search.PackageIndexingOutcome`.
extension Search {
    public enum PackageIndexing {}
}

/// Runner for a complete `packages.db` indexing pass: open the index,
/// walk the on-disk package tree, write every package row, summarise
/// the resulting database, and disconnect. GoF Strategy pattern
/// (Gamma et al, 1994).
///
/// `Indexer.PackagesService` accepts a conformer at run-time so the
/// Indexer SPM target keeps its dependency graph free of the concrete
/// Search-target actors. The composition root (the CLI's `save`
/// command) supplies a `LivePackageIndexingRunner` that wraps the
/// standard `Search.PackageIndex` + `Search.PackageIndexer` wiring.
///
/// Progress reporting goes through the typed
/// `Search.PackageIndexingProgressReporting` Observer protocol (GoF p. 293).
extension Search.PackageIndexing {
    public protocol Runner: Sendable {
        /// Run one full indexing pass and return its outcome.
        ///
        /// - Parameters:
        ///   - packagesRoot: On-disk root of extracted package archives
        ///     (typically `~/.cupertino/packages/`).
        ///   - packagesDB: Destination database file URL.
        ///   - progress: Observer receiving `(packageName, processed, total)`
        ///     reports for each package handled. Pass a Noop conformer
        ///     to opt out of progress reports.
        /// - Returns: The aggregated `Outcome`.
        func run(
            packagesRoot: URL,
            packagesDB: URL,
            progress: any Search.PackageIndexingProgressReporting
        ) async throws -> Outcome
    }

    /// Statistics emitted by a `Search.PackageIndexing.Runner` run.
    ///
    /// The Indexer translates this into its public
    /// `Indexer.PackagesService.Outcome` event payload (which keeps the
    /// same eight numeric fields).
    public struct Outcome: Sendable {
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

/// Back-compat aliases for pre-#1042 consumers.
extension Search {
    public typealias PackageIndexingRunner = PackageIndexing.Runner
    public typealias PackageIndexingOutcome = PackageIndexing.Outcome
}
