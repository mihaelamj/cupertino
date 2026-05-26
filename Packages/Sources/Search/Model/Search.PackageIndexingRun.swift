import Foundation

// MARK: - Search.PackageIndexingRunner

/// Runner for a complete `packages.db` indexing pass: open the index,
/// walk the on-disk package tree, write every package row, summarise
/// the resulting database, and disconnect. GoF Strategy pattern
/// (Gamma et al, 1994): a family of algorithms (production
/// `Search.PackageIndex` + `Search.PackageIndexer` pipeline, test
/// fixture stubs) interchangeable behind a named protocol.
///
/// `Indexer.PackagesService` accepts a conformer at run-time so the
/// Indexer SPM target keeps its dependency graph free of the concrete
/// Search-target actors. The composition root (the CLI's `save`
/// command) supplies a `LivePackageIndexingRunner` that wraps the
/// standard `Search.PackageIndex` + `Search.PackageIndexer` wiring.
///
/// This replaces the previous
/// `Search.PackageIndexingRun = @Sendable (URL, URL, callback) async throws -> Outcome`
/// closure typealias. The protocol form names the contract at the
/// constructor site (`packageIndexingRunner:`), makes captured-state
/// surface explicit on the conforming type's stored properties, and
/// produces one-line test mocks instead of multi-arg async closures.
///
/// Progress reporting goes through the typed
/// `Search.PackageIndexingProgressReporting` Observer protocol (GoF p. 293)
/// — the previous design carve-out for "genuine (name, done, total)
/// callback" closures is reversed per the standing cupertino rule
/// "no closures, they ate magic." The Indexer orchestrator
/// (`Indexer.PackagesService.run`) bridges its closure-shaped `handler:`
/// parameter to a `PackageIndexingProgressReporting` conformer before
/// invoking this method.
public extension Search {
    protocol PackageIndexingRunner: Sendable {
        /// Run one full indexing pass and return its outcome.
        ///
        /// - Parameters:
        ///   - packagesRoot: On-disk root of extracted package archives
        ///     (typically `~/.cupertino/packages/`).
        ///   - packagesDB: Destination database file URL.
        ///   - progress: Observer receiving `(packageName, processed, total)`
        ///     reports for each package handled. Pass a Noop conformer
        ///     to opt out of progress reports.
        /// - Returns: The aggregated `PackageIndexingOutcome`.
        func run(
            packagesRoot: URL,
            packagesDB: URL,
            progress: any Search.PackageIndexingProgressReporting
        ) async throws -> PackageIndexingOutcome
    }
}

// MARK: - Search.PackageIndexingOutcome

/// Statistics emitted by a `Search.PackageIndexingRunner` run.
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
