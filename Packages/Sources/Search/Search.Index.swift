import ASTIndexer
import Foundation
import LoggingModels
import SearchModels
import SharedConstants
import SharedCore
import SharedModels
import SQLite3

// MARK: - Search Index

/// SQLite FTS5-based full-text search index for documentation
extension Search {
    public actor Index {
        /// Current schema version - increment when schema changes
        /// Version history:
        /// - 1: Initial schema (docs_fts, docs_metadata, packages, package_dependencies, sample_code)
        /// - 2: Added doc_code_examples and doc_code_fts tables
        /// - 3: Added json_data column to docs_metadata for full JSON storage
        /// - 4: Added source field to docs_fts and docs_metadata for source-based filtering
        /// - 5: Added language field to docs_fts and docs_metadata (BREAKING: requires database rebuild)
        /// - 6: Added availability columns (min_ios, min_macos, etc.) for efficient filtering
        /// - 7: Previous version
        /// - 8: Added attributes column to docs_structured for @attribute indexing
        /// - 9: Added doc_symbols, doc_imports tables for SwiftSyntax AST indexing (#81)
        /// - 10: Added synonyms column to framework_aliases
        /// - 11: Added kind + symbols columns to docs_metadata (#192 section C). `kind` is
        ///       the C1 taxonomy (`symbolPage`, `article`, ...) populated by
        ///       `Search.Classify.kind(...)`. `symbols` is a denormalized text blob of
        ///       symbol names written for SQL consumers.
        /// - 12: Added `symbols` column to docs_fts (#192 section D) so bm25 can weight
        ///       directly on AST-derived symbol names. BREAKING — FTS5 does not support
        ///       ALTER TABLE ADD COLUMN, so existing DBs must be rebuilt.
        /// - 13: URL case canonicalization (#283). v12 DBs carry case-axis URI duplicates
        ///       (~30% of rows in shipped v1.0.0/v1.0.1) because the pre-#283
        ///       `URLUtilities.filename(_:)` hashed the raw case-preserving URL.
        ///       BREAKING: existing v12 DBs are rejected at open. Upgrade path is
        ///       `cupertino setup` to download the v1.0.2 bundle, which ships
        ///       pre-built at v13 with zero case-axis duplicate clusters.
        public static let schemaVersion: Int32 = 13

        // Properties are package-internal (default visibility) so the
        // SearchIndex+<Concern>.swift extension files can access them. Public
        // API surface is unchanged — internal only widens visibility within
        // this Search package, not outside.
        var database: OpaquePointer?
        let dbPath: URL
        var isInitialized = false
        /// GoF Strategy seam for log emission (1994 p. 315). Injected by
        /// the binary's composition root.
        let logger: any LoggingModels.Logging.Recording

        public init(
            dbPath: URL = Shared.Constants.defaultSearchDatabase,
            logger: any LoggingModels.Logging.Recording
        ) async throws {
            self.dbPath = dbPath
            self.logger = logger

            // Ensure directory exists
            let directory = dbPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            try await openDatabase()
            try await checkAndMigrateSchema()
            try await createTables()
            try await setSchemaVersion()
            isInitialized = true
        }

        // Note: deinit cannot access actor-isolated properties
        // SQLite connections will be closed when the process terminates
        // For explicit cleanup, call disconnect() before deallocation

        /// Close the database connection explicitly
        public func disconnect() {
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
        }

        /// Inspect `PRAGMA synchronous` on the actor's own connection
        /// (returns 0..3, matching SQLite's enum: 0=OFF, 1=NORMAL,
        /// 2=FULL, 3=EXTRA). The setting is per-connection and not
        /// persistent in the file header, so this is the only honest
        /// way to assert what the writer is actually using —
        /// `Diagnostics.Probes` opens its own connection and would
        /// see SQLite's defaults instead. Test-facing.
        public func currentSynchronousMode() -> Int32? {
            readIntegerPragma("PRAGMA synchronous;")
        }

        /// Inspect `PRAGMA journal_size_limit` on the actor's own
        /// connection (bytes, or -1 for unlimited). Same per-connection
        /// caveat as `currentSynchronousMode`.
        public func currentJournalSizeLimit() -> Int64? {
            guard let database else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, "PRAGMA journal_size_limit;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int64(stmt, 0)
        }

        private func readIntegerPragma(_ pragma: String) -> Int32? {
            guard let database else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, pragma, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int(stmt, 0)
        }

        // MARK: - Database Setup

        private func openDatabase() async throws {
            var dbPointer: OpaquePointer?

            guard sqlite3_open(dbPath.path, &dbPointer) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                sqlite3_close(dbPointer)
                throw Search.Error.sqliteError("Failed to open database: \(errorMessage)")
            }

            // Auto-retry on SQLITE_BUSY for up to 5 seconds so concurrent
            // `cupertino search` invocations against the same DB don't fail
            // immediately on transient lock contention. SQLite default is 0
            // (fail on first contention). 5 s covers idempotent open-time
            // writes (`PRAGMA user_version`, `CREATE TABLE IF NOT EXISTS`)
            // when a sibling process is doing the same.
            sqlite3_busy_timeout(dbPointer, 5000)

            // #236: WAL journal mode lets readers (`cupertino search`,
            // `cupertino ask`, `cupertino doctor`) proceed while a
            // `cupertino save --docs` writer holds the DB. PRAGMA is
            // idempotent — re-setting on an already-WAL DB is a no-op,
            // and the mode persists in the file header so subsequent
            // connections inherit it without setting again. Log and
            // continue on failure: the DB is still usable in whatever
            // mode it ended up in (default rollback journal).
            if sqlite3_exec(dbPointer, "PRAGMA journal_mode = WAL", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to enable WAL on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .search
                )
            }

            // #236 follow-up: SQLite docs explicitly recommend
            // `synchronous=NORMAL` paired with WAL mode.
            //
            //   "The synchronous=NORMAL setting provides the best
            //    balance between performance and safety for most
            //    applications running in WAL mode. You lose
            //    durability across power loss with synchronous
            //    NORMAL in WAL mode, but that is not important for
            //    most applications. Transactions are still atomic,
            //    consistent, and isolated."
            //   — https://www.sqlite.org/pragma.html#pragma_synchronous
            //
            // Default is FULL (sync at every transaction). NORMAL
            // syncs only at checkpoint boundaries. The DB stays
            // consistent at all times; only the very last commit
            // before a power loss might roll back. Cupertino's data
            // is rebuildable, so this is the right tradeoff.
            // Per-connection PRAGMA — set on every open.
            if sqlite3_exec(dbPointer, "PRAGMA synchronous = NORMAL", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to set synchronous=NORMAL on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .search
                )
            }

            // #236 follow-up: cap the WAL sidecar size. Default is
            // -1 (unlimited). SQLite docs flag three scenarios that
            // grow the WAL without bound (disabled auto-checkpoint,
            // reader starvation, very large transactions); a 64 MB
            // cap is 16× the default 1000-page (~4 MB) auto-
            // checkpoint threshold, so a healthy steady state never
            // hits it, while a pathological case truncates back to
            // 64 MB at the next checkpoint instead of growing
            // forever.
            if sqlite3_exec(dbPointer, "PRAGMA journal_size_limit = 67108864", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to set journal_size_limit on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .search
                )
            }

            database = dbPointer
        }
    }
}
