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
    /// Build a factory closure bound to the supplied `logger`. The
    /// closure constructs a `LivePerDBWriter` per destination call.
    ///
    /// **Pre-open cleanup**: deletes any stale file at the destination
    /// path AND its SQLite WAL companions (`<path>-wal`, `<path>-shm`)
    /// before opening Search.Index. The companion cleanup is safe
    /// because the migrator only runs when `detect()` returned
    /// `.migrationNeeded`, by definition meaning no live writes are
    /// in flight against these paths.
    ///
    /// **Empty indexer dict + sourceLookup**: Search.Index's
    /// `indexDocument(_:)` (the path the migrator's writer.write
    /// uses) does NOT consult the indexer dict or sourceLookup;
    /// those are read-side concerns. The factory passes
    /// `Search.SourceLookup.empty` and `[:]` rather than building
    /// dead per-destination subsets. If `indexDocument` ever starts
    /// reading the indexer dict, the migrator's contract (one writer
    /// per destination DB, multiple sources may share a destination
    /// via the view-source pattern) needs revisiting.
    public static func make(
        logger: any LoggingModels.Logging.Recording
    ) -> Distribution.PerSourceDBSplitMigrator.PerDBWriterFactory {
        { _, destinationPath in
            // Primary destinationPath: must succeed if it exists. A
            // failure here (permissions, busy file, read-only volume)
            // would let Search.Index then open the stale file and
            // surface a confusing sqlite "file is encrypted or not a
            // database" error instead of the actual cause.
            if FileManager.default.fileExists(atPath: destinationPath.path) {
                try FileManager.default.removeItem(at: destinationPath)
            }
            // WAL/SHM sidecars: best-effort cleanup. A stale -shm file
            // alone shouldn't abort the whole migration; SQLite's WAL
            // recovery handles salt-mismatched sidecars by discarding
            // the WAL. try? here is intentional asymmetry with the
            // primary path's try above.
            let sidecarPaths = [
                destinationPath.appendingPathExtension("wal"),
                destinationPath.appendingPathExtension("shm"),
                // SQLite also names them <path>-wal / <path>-shm
                // depending on whether the .db extension was already
                // present. Cover both forms defensively.
                URL(fileURLWithPath: destinationPath.path + "-wal"),
                URL(fileURLWithPath: destinationPath.path + "-shm"),
            ]
            for path in sidecarPaths where FileManager.default.fileExists(atPath: path.path) {
                try? FileManager.default.removeItem(at: path)
            }
            let searchIndex = try await Search.Index(
                dbPath: destinationPath,
                logger: logger,
                indexers: [:],
                sourceLookup: .empty
            )
            return LivePerDBWriter(searchIndex: searchIndex)
        }
    }
}
