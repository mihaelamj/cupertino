import Foundation
import IndexerModels
import SearchModels
import SharedConstants

// MARK: - Indexer.PackagesService — concrete `run` orchestrator
//
// The value types (`Request`, `Outcome`, `Event`) plus the
// `Indexer.PackagesService.EventObserving` Observer protocol live in the
// foundation-only `IndexerModels` seam target. This file extends the
// same `Indexer.PackagesService` namespace to add the actual
// orchestrator behaviour.

extension Indexer.PackagesService {
    /// Build `packages.db` from extracted package archives at
    /// `~/.cupertino/packages/<owner>/<repo>/`. Wraps an injected
    /// `Search.PackageIndexingRunner` conformer with event-emission so
    /// this target doesn't import `Search` directly — the CLI
    /// composition root supplies a `LivePackageIndexingRunner` backed
    /// by `Search.PackageIndex` + `Search.PackageIndexer`.
    public static func run(
        _ request: Request,
        packageIndexingRunner: any Search.PackageIndexingRunner,
        events: any EventObserving
    ) async throws -> Outcome {
        events.observe(event: .starting(
            packagesRoot: request.packagesRoot,
            packagesDB: request.packagesDB
        ))

        if request.clear, FileManager.default.fileExists(atPath: request.packagesDB.path) {
            events.observe(event: .removingExistingDB(request.packagesDB))
            try FileManager.default.removeItem(at: request.packagesDB)
        }

        let reporter = EventsToProgressReporter(events: events)
        let result = try await packageIndexingRunner.run(
            packagesRoot: request.packagesRoot,
            packagesDB: request.packagesDB,
            progress: reporter
        )

        let outcome = Outcome(
            packagesIndexed: result.packagesIndexed,
            packagesFailed: result.packagesFailed,
            totalFiles: result.totalFiles,
            totalBytes: result.totalBytes,
            durationSeconds: result.durationSeconds,
            totalPackagesInDB: result.totalPackagesInDB,
            totalFilesInDB: result.totalFilesInDB,
            totalBytesInDB: result.totalBytesInDB
        )
        events.observe(event: .finished(outcome))
        return outcome
    }

    /// Adapter bridging the typed `Indexer.PackagesService.EventObserving`
    /// Observer protocol (from `IndexerModels`) to the typed
    /// `Search.PackageIndexingProgressReporting` Observer protocol that
    /// `Search.PackageIndexingRunner.run` requires. Pure
    /// protocol-to-protocol adapter — no closures involved.
    private struct EventsToProgressReporter: Search.PackageIndexingProgressReporting {
        let events: any EventObserving

        func report(packageName: String, processed: Int, total: Int) {
            events.observe(event: .progress(name: packageName, done: processed, total: total))
        }
    }
}
