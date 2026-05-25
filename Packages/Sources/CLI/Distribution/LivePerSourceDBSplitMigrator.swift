import Distribution
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants

// MARK: - LivePerDBWriter (step 6c-ii-a)

/// Production `Distribution.PerSourceDBSplitMigrator.PerDBWriter`
/// conformer. Wraps a `Search.Index` instance opened at the
/// destination DB path; forwards `write(_:)` to `indexDocument(_:)`,
/// `rowCount()` to `documentCount()`, and `disconnect()` to the
/// actor's own disconnect.
///
/// Constructed by `LivePerDBWriterFactory.make(destination:path:)`,
/// which is the closure the migrator's `migrate(...)` method calls
/// per destination DB. The factory opens a fresh `Search.Index` at
/// the destination path with a single-entry indexer dict keyed by
/// the destination descriptor's `id` (the migrator does not need a
/// multi-source indexer dict because each destination DB receives
/// rows from exactly one source-id during the migration).
///
/// Step 6c-iii wires this into `cupertino setup`'s post-extract
/// flow + `cupertino save`'s first-run hook.
public actor LivePerDBWriter: Distribution.PerSourceDBSplitMigrator.PerDBWriter {
    private let searchIndex: Search.Index
    private var isDisconnected = false

    public init(searchIndex: Search.Index) {
        self.searchIndex = searchIndex
    }

    public func write(_ row: Distribution.PerSourceDBSplitMigrator.LegacyRow) async throws {
        precondition(!isDisconnected, "LivePerDBWriter.write after disconnect")
        try await searchIndex.indexDocument(row)
    }

    public func rowCount() async throws -> Int {
        precondition(!isDisconnected, "LivePerDBWriter.rowCount after disconnect")
        return try await searchIndex.documentCount()
    }

    public func disconnect() async {
        guard !isDisconnected else { return }
        isDisconnected = true
        await searchIndex.disconnect()
    }
}

// MARK: - LivePerDBWriterFactory

/// Factory for `LivePerDBWriter` instances. Used as the
/// `PerDBWriterFactory` closure passed to
/// `Distribution.PerSourceDBSplitMigrator.migrate(...)`.
///
/// The factory clears any existing file at the destination path
/// BEFORE opening Search.Index, so the migration produces a fresh DB
/// (no leftover rows from a partial prior run). This is safe because
/// the migrator runs only when `detect()` returns `.migrationNeeded`,
/// which by definition means no non-empty split DBs exist yet.
public enum LivePerDBWriterFactory {
    /// Build a factory closure bound to the supplied registry +
    /// logger. The closure constructs a `LivePerDBWriter` per
    /// destination call; the registry lookup at construction time
    /// yields the per-destination indexer dict (single entry today,
    /// since the migrator writes one source's rows per destination).
    public static func make(
        registry: Search.SourceRegistry,
        logger: any LoggingModels.Logging.Recording
    ) -> Distribution.PerSourceDBSplitMigrator.PerDBWriterFactory {
        { destination, destinationPath in
            // Fresh DB: delete any stale file from a partial prior run.
            if FileManager.default.fileExists(atPath: destinationPath.path) {
                try FileManager.default.removeItem(at: destinationPath)
            }
            // Look up the provider whose destinationDB matches; build
            // a single-entry indexer dict keyed by its source-id. The
            // migrator routes rows whose source-id matches the provider
            // through this indexer at indexDocument time.
            let indexers: [String: any Search.SourceIndexer] = registry.allEnabled
                .filter { $0.destinationDB == destination }
                .reduce(into: [:]) { dict, provider in
                    dict[provider.definition.id] = provider.makeIndexer()
                }
            let sourceLookup = Search.SourceLookup(
                definitions: registry.allEnabled.map(\.definition)
            )
            let searchIndex = try await Search.Index(
                dbPath: destinationPath,
                logger: logger,
                indexers: indexers,
                sourceLookup: sourceLookup
            )
            return LivePerDBWriter(searchIndex: searchIndex)
        }
    }
}
