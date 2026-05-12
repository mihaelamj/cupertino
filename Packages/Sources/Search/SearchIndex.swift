import ASTIndexer
import Foundation
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

        public init(
            dbPath: URL = Shared.Constants.defaultSearchDatabase
        ) async throws {
            self.dbPath = dbPath

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

            database = dbPointer
        }
    }
}
