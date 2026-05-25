import Distribution
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import SQLite3

// MARK: - LiveLegacyDBReader (step 6c-ii-b)

/// Production `Distribution.PerSourceDBSplitMigrator.LegacyDBReader`
/// conformer. Opens the legacy `search.db` file via raw sqlite3 in
/// read-only mode + runs the two queries the migrator needs:
///
///   1. `SELECT source, COUNT(*) FROM docs_metadata GROUP BY source`
///      for `sourceIDCounts()`.
///   2. `SELECT m.<fields...>, f.title, f.content
///       FROM docs_metadata m LEFT JOIN docs_fts f ON m.uri = f.uri
///       WHERE m.source = ?` for `rows(forSourceID:)`.
///
/// Read-only mode (`SQLITE_OPEN_READONLY`) makes this safe to use
/// alongside the active read path during step 6c-iii's transition
/// (production code still reads the legacy file via `Search.Index`
/// in read-write mode for non-migration queries; the migrator's
/// reader is a parallel read-only connection).
///
/// The reader does NOT validate the schema beyond what the queries
/// require. Schema-validation (`DetectionOutcome.legacyFileMalformed`)
/// is a future-step concern; today the reader fails the
/// `sourceIDCounts()` call with an `sqliteError` if the
/// `docs_metadata` table is missing, which the migrator wraps as
/// `MigrationError.ioFailure`.
public actor LiveLegacyDBReader: Distribution.PerSourceDBSplitMigrator.LegacyDBReader {
    private let dbPath: URL
    private var connection: OpaquePointer?
    private var isOpen = false

    public init(legacyFile: URL) {
        dbPath = legacyFile
    }

    private func openIfNeeded() throws {
        guard !isOpen else { return }
        let status = sqlite3_open_v2(dbPath.path, &connection, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK else {
            let message = connection.flatMap { sqlite3_errmsg($0).flatMap { String(cString: $0) } } ?? "sqlite3_open_v2 status=\(status)"
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw LegacyReaderError.openFailed(path: dbPath.path, reason: message)
        }
        isOpen = true
    }

    private func close() {
        guard isOpen, let connection else { return }
        sqlite3_close(connection)
        self.connection = nil
        isOpen = false
    }

    // No deinit: Swift actors can't access actor-isolated state from
    // a nonisolated deinit, and the SQLite connection MUST be closed
    // from an isolated context to avoid the connection being torn
    // down mid-step. Callers should call `close()` explicitly via the
    // migrator's per-source flow (which already drains the stream
    // before the next source's iteration). At-exit cleanup falls
    // through to the OS reclaiming SQLite's file handle.

    public func sourceIDCounts() async throws -> [String: Int] {
        try openIfNeeded()
        guard let connection else {
            throw LegacyReaderError.openFailed(path: dbPath.path, reason: "connection unexpectedly nil")
        }
        let sql = "SELECT source, COUNT(*) FROM docs_metadata GROUP BY source"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let prepareStatus = sqlite3_prepare_v2(connection, sql, -1, &stmt, nil)
        guard prepareStatus == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(connection))
            throw LegacyReaderError.queryFailed(sql: sql, reason: message)
        }
        var counts: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sourceC = sqlite3_column_text(stmt, 0) else { continue }
            let source = String(cString: sourceC)
            let count = Int(sqlite3_column_int64(stmt, 1))
            counts[source] = count
        }
        return counts
    }

    public nonisolated func rows(
        forSourceID sourceID: String
    ) -> AsyncThrowingStream<Distribution.PerSourceDBSplitMigrator.LegacyRow, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.streamRows(forSourceID: sourceID, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamRows(
        forSourceID sourceID: String,
        continuation: AsyncThrowingStream<Distribution.PerSourceDBSplitMigrator.LegacyRow, Error>.Continuation
    ) async throws {
        try openIfNeeded()
        guard let connection else {
            throw LegacyReaderError.openFailed(path: dbPath.path, reason: "connection unexpectedly nil")
        }
        // Column order MUST match the IndexDocumentParams init order
        // below. SELECT lists the metadata fields in init-parameter
        // order, then title + content from the FTS join.
        let sql = """
        SELECT m.uri, m.source, m.framework, m.language, m.file_path, m.content_hash,
               m.last_crawled, m.source_type, m.package_id, m.json_data,
               m.min_ios, m.min_macos, m.min_tvos, m.min_watchos, m.min_visionos,
               m.availability_source, f.title, f.content
        FROM docs_metadata m
        LEFT JOIN docs_fts f ON m.uri = f.uri
        WHERE m.source = ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(connection, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw LegacyReaderError.queryFailed(sql: sql, reason: String(cString: sqlite3_errmsg(connection)))
        }
        sqlite3_bind_text(stmt, 1, (sourceID as NSString).utf8String, -1, nil)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = Self.buildRow(stmt: stmt!)
            continuation.yield(row)
        }
        continuation.finish()
    }

    /// Read a single row's 18 columns into IndexDocumentParams.
    /// NULL columns return Swift nil for optional fields; required
    /// fields fall back to empty string when SQLite returns NULL
    /// (defensive: docs_metadata schema declares NOT NULL on the
    /// required columns, but the reader is defensive against legacy
    /// corruption).
    private static func buildRow(stmt: OpaquePointer) -> Distribution.PerSourceDBSplitMigrator.LegacyRow {
        Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: textColumn(stmt: stmt, index: 0) ?? "",
            source: textColumn(stmt: stmt, index: 1) ?? "",
            framework: textColumn(stmt: stmt, index: 2),
            language: textColumn(stmt: stmt, index: 3),
            title: textColumn(stmt: stmt, index: 16) ?? "",
            content: textColumn(stmt: stmt, index: 17) ?? "",
            filePath: textColumn(stmt: stmt, index: 4) ?? "",
            contentHash: textColumn(stmt: stmt, index: 5) ?? "",
            lastCrawled: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 6))),
            sourceType: textColumn(stmt: stmt, index: 7) ?? Shared.Constants.Database.defaultSourceTypeApple,
            packageId: optionalIntColumn(stmt: stmt, index: 8),
            jsonData: textColumn(stmt: stmt, index: 9),
            minIOS: textColumn(stmt: stmt, index: 10),
            minMacOS: textColumn(stmt: stmt, index: 11),
            minTvOS: textColumn(stmt: stmt, index: 12),
            minWatchOS: textColumn(stmt: stmt, index: 13),
            minVisionOS: textColumn(stmt: stmt, index: 14),
            availabilitySource: textColumn(stmt: stmt, index: 15)
        )
    }

    private static func textColumn(stmt: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private static func optionalIntColumn(stmt: OpaquePointer, index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, index))
    }

    public enum LegacyReaderError: Error, Sendable, Equatable {
        case openFailed(path: String, reason: String)
        case queryFailed(sql: String, reason: String)
    }
}

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
