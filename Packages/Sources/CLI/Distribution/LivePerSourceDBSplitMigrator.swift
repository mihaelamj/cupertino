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
    /// **Pre-open cleanup, foreign-table-aware (#1037)**: the legacy
    /// behaviour (unconditional wipe) is correct ONLY when the
    /// destination is exclusively a Search.Index DB. Post-#1037 the
    /// `apple-sample-code.db` destination also carries
    /// `Sample.Index.Builder`'s rich schema (`projects`, `files`,
    /// `file_symbols`, `file_imports`); wiping that file destroys
    /// rich-schema rows that the user built via `cupertino save
    /// --samples`. The migrator therefore checks for the `projects`
    /// table BEFORE the wipe; if it is present the destination file
    /// is preserved AND we just open Search.Index on top of it
    /// (which creates `docs_metadata` + `docs_fts` alongside the
    /// existing tables on first open). WAL/SHM cleanup still runs in
    /// both branches because the migrator only fires when
    /// `detect()` returned `.migrationNeeded`, by definition meaning
    /// no live writes are in flight; SQLite's WAL recovery handles
    /// salt-mismatched sidecars by discarding the WAL.
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
            // Foreign-table check (#1037): preserve the destination
            // file when it carries Sample.Index rich data so the
            // migrator does not destroy it on its way into the shared
            // file. Logged so an operator inspecting the migrate(...)
            // output sees explicitly which destinations took the
            // preserve path vs the wipe path.
            let preserveDestination =
                FileManager.default.fileExists(atPath: destinationPath.path) &&
                hasForeignSampleIndexTables(at: destinationPath)

            if preserveDestination {
                logger.info(
                    "Migrator: preserving existing destination \(destinationPath.lastPathComponent) " +
                        "because it carries Sample.Index tables (rich-schema data " +
                        "from `cupertino save --samples`). Search.Index will open " +
                        "on top of the file and create its own tables alongside.",
                    category: .cli
                )
            } else if FileManager.default.fileExists(atPath: destinationPath.path) {
                // Primary destinationPath: must succeed if it exists. A
                // failure here (permissions, busy file, read-only volume)
                // would let Search.Index then open the stale file and
                // surface a confusing sqlite "file is encrypted or not a
                // database" error instead of the actual cause.
                try FileManager.default.removeItem(at: destinationPath)
            }
            // WAL/SHM sidecars cleanup. In the wipe branch the main
            // file is already gone, so any companions left behind would
            // confuse SQLite on the fresh open and must be cleared. In
            // the PRESERVE branch we must NOT delete the companions:
            // they might carry un-checkpointed Sample.Index writes from
            // a prior `cupertino save --samples` that exited before
            // SQLite auto-checkpointed (the .migrationNeeded
            // precondition the migrator inherits is about Search.Index,
            // not Sample.Index; nothing guarantees the WAL is empty
            // there). Trusting SQLite's own WAL recovery on the next
            // open preserves any committed-but-uncheckpointed Sample.Index
            // pages.
            if !preserveDestination {
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

    /// Inspect the destination DB for a `projects` table, the
    /// canonical marker that `Sample.Index.Builder` has written its
    /// rich schema here.
    ///
    /// **Name-only match (intentional)**: the check looks at the
    /// table NAME only, not its column shape, so any future pipeline
    /// that introduces a sibling table also named `projects` would
    /// trigger the preserve path here. Today there is no such other
    /// pipeline; if one is added, this helper must be tightened (e.g.
    /// require a sentinel column like `min_visionos` that's specific
    /// to `Sample.Index.Builder`'s schema). The narrower the match,
    /// the lower the false-positive rate but the higher the
    /// false-negative rate as the Sample.Index schema evolves; the
    /// name-only check trades the latter for the former.
    ///
    /// **Outcomes (defensive default = preserve, but only when there
    /// is plausibly SQLite data to preserve)**:
    /// - `SQLITE_ROW` on the sqlite_master query: the `projects` table
    ///   is present → return `true` (preserve the file).
    /// - `SQLITE_DONE`: we successfully read sqlite_master and
    ///   confirmed no `projects` row → return `false` (wipe is safe).
    /// - prepare or step fails with `SQLITE_NOTADB`: the file is
    ///   definitively not a SQLite database (e.g. zero-byte stub,
    ///   stale raw bytes) → return `false` (wipe is safe; there's
    ///   nothing to preserve).
    /// - prepare or step fails with `SQLITE_BUSY` / `SQLITE_LOCKED`
    ///   / `SQLITE_CORRUPT` / `SQLITE_IOERR` / other → return `true`
    ///   (preserve as the safer default; the file IS a SQLite file
    ///   but transiently unreadable, so wiping risks destroying real
    ///   data. Search.Index will surface the actual error to the user
    ///   when it tries to open the same file itself).
    /// - `sqlite3_open_v2` fails entirely (path resolution, permission)
    ///   → return `false` (file can't even be opened; wipe path will
    ///   surface the same underlying error to the user).
    private static func hasForeignSampleIndexTables(at path: URL) -> Bool {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            // Open itself failed. SQLite's sqlite3_open_v2 returns OK
            // for nearly anything that exists; an outright failure here
            // is exotic (path resolution / permissions). Fall through
            // to wipe so the user sees the real error from the next
            // step, not silently-preserved unreachable state.
            return false
        }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='projects' LIMIT 1"
        let prepareCode = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareCode == SQLITE_OK else {
            // Prepare failed. Differentiate "not a SQLite file"
            // (wipe-safe) from transient errors (preserve).
            switch prepareCode {
            case SQLITE_NOTADB:
                return false
            default:
                return true
            }
        }
        let step = sqlite3_step(stmt)
        switch step {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            // Confirmed no projects table; wipe is safe.
            return false
        case SQLITE_NOTADB:
            return false
        default:
            // SQLITE_BUSY / SQLITE_LOCKED / SQLITE_CORRUPT / SQLITE_IOERR
            // etc. The query couldn't run to completion; we don't know
            // what's in the file. Preserve.
            return true
        }
    }
}
