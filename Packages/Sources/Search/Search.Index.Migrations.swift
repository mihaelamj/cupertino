import Foundation
import SearchModels
import SharedCore
import SharedModels
import SQLite3

extension Search.Index {
    func getSchemaVersion() -> Int32 {
        guard let database else { return 0 }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return sqlite3_column_int(statement, 0)
    }

    func setSchemaVersion() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Skip the write if the on-disk version already matches. Every
        // `Search.Index.init` (i.e. every `cupertino search`) used to issue
        // this PRAGMA unconditionally; on the steady-state path where the
        // version is already correct, that write produced nothing useful
        // but did require a write lock on the DB. Two concurrent searches
        // would then contend (SQLite is single-writer) and one would fail
        // with `database is locked`.
        if getSchemaVersion() == Self.schemaVersion {
            return
        }

        let sql = "PRAGMA user_version = \(Self.schemaVersion)"
        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            throw Search.Error.sqliteError("Failed to set schema version: \(errorMessage)")
        }
    }

    func checkAndMigrateSchema() async throws {
        let currentVersion = getSchemaVersion()

        // New database - no migration needed
        if currentVersion == 0 {
            return
        }

        // Future version - incompatible
        if currentVersion > Self.schemaVersion {
            throw Search.Error.sqliteError(
                "Database schema version \(currentVersion) is newer than supported version \(Self.schemaVersion). "
                    + "Please update cupertino or delete the database to recreate it."
            )
        }

        // Migrate from older versions
        if currentVersion < 2 {
            // Version 1 -> 2: Added doc_code_examples and doc_code_fts tables
            // These are created with IF NOT EXISTS in createTables(), so no explicit migration needed
        }

        if currentVersion < 3 {
            // Version 2 -> 3: Added json_data column to docs_metadata
            try await migrateToVersion3()
        }

        if currentVersion < 4 {
            // Version 3 -> 4: Added source field to docs_fts and docs_metadata
            // FTS5 tables cannot have columns added, so full reindex is required.
            // Delete the database file and run cupertino save to rebuild.
            try await migrateToVersion4()
        }

        if currentVersion < 5 {
            // Version 4 -> 5: Added language field to docs_fts and docs_metadata
            // BREAKING CHANGE: FTS5 tables cannot have columns added.
            // Database must be deleted and rebuilt with 'cupertino save'.
            throw Search.Error.sqliteError(
                "Database schema version \(currentVersion) requires migration to version 5. " +
                    "This is a breaking change that adds the 'language' field. " +
                    "Please delete the database and run 'cupertino save' to rebuild: " +
                    "rm \(dbPath.path) && cupertino save"
            )
        }

        if currentVersion < 6 {
            // Version 5 -> 6: Added availability columns to docs_metadata
            try await migrateToVersion6()
        }

        if currentVersion < 7 {
            // Version 6 -> 7: Added availability columns to sample_code_metadata
            try await migrateToVersion7()
        }

        // Version 8 -> 9: New tables created with IF NOT EXISTS in createTables()
        // No explicit migration needed for doc_symbols, doc_symbols_fts, doc_imports

        if currentVersion < 10 {
            // Version 9 -> 10: Added synonyms column to framework_aliases
            try await migrateToVersion10()
        }

        if currentVersion < 11 {
            // Version 10 -> 11: Added kind + symbols columns to docs_metadata (#192 C).
            // Uses ALTER TABLE ADD COLUMN — existing rows get the DEFAULT value
            // ('unknown' for kind, NULL for symbols). A subsequent re-crawl
            // repopulates via Classify.kind(...) and the AST pass.
            try await migrateToVersion11()
        }

        if currentVersion < 12 {
            // Version 11 -> 12: Added `symbols` column to docs_fts (#192 D) so
            // bm25 can weight directly on AST-extracted symbol names. FTS5
            // does not support ALTER TABLE ADD COLUMN on virtual tables, so
            // this is a BREAKING change — existing DBs must be rebuilt.
            throw Search.Error.sqliteError(
                "Database schema version \(currentVersion) requires migration to version 12. " +
                    "This is a breaking change that adds AST-derived symbols to the FTS index. " +
                    "Please delete the database and run 'cupertino save' to rebuild: " +
                    "rm \(dbPath.path) && cupertino save"
            )
        }

        if currentVersion < 13 {
            // Version 12 -> 13: URL case canonicalization (#283). v12 DBs
            // carry case-axis duplicate URIs (61,257 clusters / 122,522 rows
            // in the shipped v1.0.0 bundle, ~30% of the corpus). The fix in
            // `URLUtilities.filename(_:)` makes new crawls produce canonical
            // URIs. The v1.0.2 bundle ships pre-built at v13, so `cupertino
            // setup` is the production upgrade path.
            throw Search.Error.sqliteError(
                "Database schema version \(currentVersion) requires migration to version 13. " +
                    "This is a breaking change that drops case-axis duplicate URIs (#283). " +
                    "Please delete the database and run 'cupertino setup' to download the " +
                    "pre-built v1.0.2 bundle: " +
                    "rm \(dbPath.path) && cupertino setup"
            )
        }
    }

    func migrateToVersion11() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let statements = [
            "ALTER TABLE docs_metadata ADD COLUMN kind TEXT NOT NULL DEFAULT 'unknown';",
            "ALTER TABLE docs_metadata ADD COLUMN symbols TEXT;",
            "CREATE INDEX IF NOT EXISTS idx_kind ON docs_metadata(kind);",
        ]

        for sql in statements {
            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }
            // Ignore error if column/index already exists — this keeps the
            // migration idempotent across partial runs.
            sqlite3_exec(database, sql, nil, nil, &errorPointer)
        }
    }

    func migrateToVersion10() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = "ALTER TABLE framework_aliases ADD COLUMN synonyms TEXT;"

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        // Ignore error if column already exists
        sqlite3_exec(database, sql, nil, nil, &errorPointer)
    }

    func migrateToVersion7() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Add availability columns to sample_code_metadata
        let columns = [
            "ALTER TABLE sample_code_metadata ADD COLUMN min_ios TEXT;",
            "ALTER TABLE sample_code_metadata ADD COLUMN min_macos TEXT;",
            "ALTER TABLE sample_code_metadata ADD COLUMN min_tvos TEXT;",
            "ALTER TABLE sample_code_metadata ADD COLUMN min_watchos TEXT;",
            "ALTER TABLE sample_code_metadata ADD COLUMN min_visionos TEXT;",
        ]

        var errorPointer: UnsafeMutablePointer<CChar>?

        for sql in columns {
            sqlite3_free(errorPointer)
            errorPointer = nil
            _ = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        }

        sqlite3_free(errorPointer)
    }

    func migrateToVersion6() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Add availability columns - these can be added with ALTER TABLE
        let columns = [
            "ALTER TABLE docs_metadata ADD COLUMN min_ios TEXT;",
            "ALTER TABLE docs_metadata ADD COLUMN min_macos TEXT;",
            "ALTER TABLE docs_metadata ADD COLUMN min_tvos TEXT;",
            "ALTER TABLE docs_metadata ADD COLUMN min_watchos TEXT;",
            "ALTER TABLE docs_metadata ADD COLUMN min_visionos TEXT;",
            "ALTER TABLE docs_metadata ADD COLUMN availability_source TEXT;",
        ]

        var errorPointer: UnsafeMutablePointer<CChar>?

        for sql in columns {
            // This will fail silently if column already exists
            sqlite3_free(errorPointer)
            errorPointer = nil
            _ = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        }

        sqlite3_free(errorPointer)

        // Create indexes for efficient filtering
        let indexes = [
            "CREATE INDEX IF NOT EXISTS idx_min_ios ON docs_metadata(min_ios);",
            "CREATE INDEX IF NOT EXISTS idx_min_macos ON docs_metadata(min_macos);",
            "CREATE INDEX IF NOT EXISTS idx_min_tvos ON docs_metadata(min_tvos);",
            "CREATE INDEX IF NOT EXISTS idx_min_watchos ON docs_metadata(min_watchos);",
            "CREATE INDEX IF NOT EXISTS idx_min_visionos ON docs_metadata(min_visionos);",
        ]

        for sql in indexes {
            errorPointer = nil
            _ = sqlite3_exec(database, sql, nil, nil, &errorPointer)
            sqlite3_free(errorPointer)
        }
    }

    func migrateToVersion4() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Add source column to docs_metadata (this can be done with ALTER)
        let sql = "ALTER TABLE docs_metadata ADD COLUMN source TEXT NOT NULL DEFAULT 'apple-docs';"
        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        // This will fail silently if column already exists
        _ = sqlite3_exec(database, sql, nil, nil, &errorPointer)

        // Note: FTS5 tables require recreation to add columns.
        // The new schema will be created on next save, old data will be replaced.
    }

    func migrateToVersion3() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Add json_data column if it doesn't exist
        let sql = "ALTER TABLE docs_metadata ADD COLUMN json_data TEXT;"
        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        // This will fail silently if column already exists, which is fine
        _ = sqlite3_exec(database, sql, nil, nil, &errorPointer)
    }
}
