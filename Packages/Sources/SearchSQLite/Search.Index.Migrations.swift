import Foundation
import SearchModels
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
        let currentVersion = getSchemaVersion()
        if currentVersion == Self.schemaVersion {
            return
        }

        // #635 — defense in depth. Only stamp when the DB is fresh
        // (`user_version = 0`). Any other mismatch means
        // `checkAndMigrateSchema` either ran an explicit migrator that
        // updated the schema in place (the legitimate path) or
        // silently fell through without recognising the version
        // (the bug — happened with #77's schemaVersion 13 → 14 bump
        // before the v13→v14 migrator entry was added; my dev binary
        // smoke stamped the user's brew-managed DB at 14 while the
        // homebrew binary still expected 13). The migrator entries
        // are the primary defense; this guard catches the case where
        // a future schema bump forgets to add one. Throwing here is
        // strictly safer than silently stamping: the user sees a
        // clear error and runs `cupertino setup` to rebuild rather
        // than a different binary breaking on next open.
        guard currentVersion == 0 else {
            throw Search.Error.sqliteError(
                "Refusing to stamp PRAGMA user_version=\(Self.schemaVersion) " +
                    "on a DB at user_version=\(currentVersion). " +
                    "Either a migrator entry is missing in `checkAndMigrateSchema` " +
                    "for the \(currentVersion) → \(Self.schemaVersion) path, or this " +
                    "binary is being run against a database produced by a different " +
                    "build. Run `cupertino setup` to redownload a matching bundle."
            )
        }

        try stampUserVersionUnchecked(Self.schemaVersion)
    }

    /// Unguarded helper that writes `PRAGMA user_version = <version>`.
    /// **Bypasses** the #635 fresh-DB guard in `setSchemaVersion()` because
    /// each in-place migrator already knows it just successfully migrated
    /// to its target version. Without this helper, in-place migrators have
    /// no legitimate way to advance the on-disk version stamp and the
    /// next-open setSchemaVersion call trips the guard (#749).
    ///
    /// Callers:
    /// - Every in-place migrator (`migrateToVersion3` / `4` / `6` / `7` /
    ///   `10` / `11` / `16` / `17`) — stamps the version it migrated to
    ///   as the final step.
    /// - `setSchemaVersion()` itself for the fresh-DB (`user_version=0`)
    ///   path; this consolidates the actual sqlite3 write here so future
    ///   schema bumps cannot accidentally introduce two different write
    ///   paths.
    ///
    /// Errors propagate as `Search.Error.sqliteError`; refuses to swallow
    /// the failure the way the historical migrator `sqlite3_exec(...) →
    /// ignored errorPointer` pattern does for ALTER TABLE statements.
    /// The PRAGMA write is the load-bearing step; silent failure here is
    /// the class-of-bug we are closing.
    func stampUserVersionUnchecked(_ version: Int32) throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = "PRAGMA user_version = \(version)"
        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            throw Search.Error.sqliteError("Failed to stamp PRAGMA user_version=\(version): \(errorMessage)")
        }
    }

    // swiftlint:disable:next function_body_length
    func checkAndMigrateSchema() async throws {
        let currentVersion = getSchemaVersion()

        // New database - no migration needed
        if currentVersion == 0 {
            return
        }

        // Future version - incompatible.
        // #673 Phase E — typed error so CLI can map to EX_DATAERR + print
        // the brew-upgrade remediation without a Swift stack trace.
        if currentVersion > Self.schemaVersion {
            throw Search.Error.schemaVersionMismatch(
                currentDBVersion: Int(currentVersion),
                expectedBinaryVersion: Int(Self.schemaVersion),
                dbPath: dbPath.path
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
            // Version 4 -> 5: Added language field to docs_fts and docs_metadata.
            // BREAKING CHANGE: FTS5 tables cannot have columns added.
            // #673 Phase E — typed error; CLI prints user-friendly remediation.
            throw Search.Error.schemaVersionMismatch(
                currentDBVersion: Int(currentVersion),
                expectedBinaryVersion: Int(Self.schemaVersion),
                dbPath: dbPath.path
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
            // #673 Phase E — typed error; CLI prints user-friendly remediation.
            throw Search.Error.schemaVersionMismatch(
                currentDBVersion: Int(currentVersion),
                expectedBinaryVersion: Int(Self.schemaVersion),
                dbPath: dbPath.path
            )
        }

        if currentVersion < 13 {
            // Version 12 -> 13: URL case canonicalization (#283). v12 DBs
            // carry case-axis duplicate URIs (61,257 clusters / 122,522 rows
            // in the shipped v1.0.0 bundle, ~30% of the corpus). The fix in
            // `URLUtilities.filename(_:)` makes new crawls produce canonical
            // URIs. The v1.0.2 bundle ships pre-built at v13, so `cupertino
            // setup` is the production upgrade path.
            // #673 Phase E — typed error; CLI prints user-friendly remediation.
            throw Search.Error.schemaVersionMismatch(
                currentDBVersion: Int(currentVersion),
                expectedBinaryVersion: Int(Self.schemaVersion),
                dbPath: dbPath.path
            )
        }

        if currentVersion < 14 {
            // Version 13 -> 14: Added `symbol_components` column to docs_fts
            // (#77 / #634). FTS5 does not support ALTER TABLE ADD COLUMN on
            // virtual tables, so this is a BREAKING change — existing DBs
            // must be rebuilt.
            //
            // #635 — this entry was missing in #634's initial schema bump;
            // its absence caused `setSchemaVersion` to silently stamp
            // user_version=14 on any v13 DB the new binary opened, which
            // then locked out other binaries (homebrew 1.1.0 at schema 13)
            // from reading the same DB. The pattern matches the v11→v12
            // and v12→v13 throws above; the only safe upgrade path is a
            // full rebuild via `cupertino setup`.
            // #673 Phase E — typed error; CLI prints user-friendly remediation.
            throw Search.Error.schemaVersionMismatch(
                currentDBVersion: Int(currentVersion),
                expectedBinaryVersion: Int(Self.schemaVersion),
                dbPath: dbPath.path
            )
        }

        if currentVersion < 15 {
            // Version 14 -> 15: Added `inheritance` edge table (#274).
            // Existing v14 DBs have no rows to walk; the only meaningful
            // upgrade path is a re-index that re-runs the indexer over
            // the same JSON and populates the new table. Pattern
            // matches v11→v12 / v12→v13 / v13→v14 — `cupertino setup`
            // for the production-ready bundle, or rebuild locally.
            // #673 Phase E — typed error; CLI prints user-friendly remediation.
            throw Search.Error.schemaVersionMismatch(
                currentDBVersion: Int(currentVersion),
                expectedBinaryVersion: Int(Self.schemaVersion),
                dbPath: dbPath.path
            )
        }

        if currentVersion < 16 {
            // Version 15 -> 16: Added `implementation_swift_version`
            // column to `docs_metadata` (#225 Part B). Captures the
            // Swift toolchain version a swift-evolution proposal landed
            // in. Unlike v14→v15 (which had to throw because the new
            // `inheritance` table needed walk data only available via a
            // full re-index), this is a clean in-place ALTER TABLE ADD
            // COLUMN — old rows get NULL, new indexing populates the
            // column for swift-evolution rows, every other source stays
            // NULL by design. NULL semantics match the #226 platform
            // filter: a row with no value is rejected when `--swift` is
            // set, passed through when it isn't.
            try await migrateToVersion16()
        }

        if currentVersion < 17 {
            // Version 16 -> 17: Added `generic_constraints` column to
            // `doc_symbols` (#755). The pre-fix `generic_params` column
            // stored only type-parameter names (`T`, `Element`); the
            // MCP `search_generics` tool advertised constraint search
            // but the corpus carried only 17 rows of constraint-form
            // data out of 351,495. The new column carries the
            // constraint half of `T: Collection` form harvested from
            // the AST extractor + where-clause patterns parsed from
            // the `signature` column at index time. Clean in-place
            // ALTER TABLE ADD COLUMN, old rows get NULL, the next
            // `cupertino save --source apple-docs` re-index populates the column.
            // Same NULL semantics as v15-to-v16: filters reject NULL
            // rows when set, pass through when not set.
            try await migrateToVersion17()
        }

        if currentVersion < 18 {
            // Version 17 -> 18: DROP the `packages` and
            // `package_dependencies` tables from search.db (#789). The
            // canonical packages store is `packages.db`, built by
            // `cupertino save --source packages` and queried by `cupertino
            // package-search`. The in-search.db tables were a shallow
            // duplicate fed from a slimmed-to-empty bundled catalog.
            // Clean in-place DROP TABLE IF EXISTS, no data preserved
            // (the table was empty for end users by the time v17 shipped
            // anyway since the catalog had been slimmed to URL-only and
            // returned empty at runtime).
            try await migrateToVersion18()
        }
    }

    /// v15 → v16: add `implementation_swift_version` to docs_metadata
    /// (#225 Part B). In-place column add; safe for both fresh DBs
    /// (the column is also declared in the initial CREATE TABLE so a
    /// v16 build coming up against a brand-new DB never enters this
    /// path) and existing v15 DBs (the column starts NULL and gets
    /// populated on the next re-index).
    ///
    /// The trailing `stampUserVersionUnchecked(16)` is load-bearing
    /// per #749 — the #635 guard in `setSchemaVersion()` refuses to
    /// stamp non-fresh DBs, so each in-place migrator is responsible
    /// for stamping the version it migrated to.
    func migrateToVersion16() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let statements = [
            "ALTER TABLE docs_metadata ADD COLUMN implementation_swift_version TEXT;",
            "CREATE INDEX IF NOT EXISTS idx_implementation_swift_version ON docs_metadata(implementation_swift_version);",
        ]

        for sql in statements {
            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }
            // Ignore error if column/index already exists — keeps the
            // migration idempotent across partial runs. Matches the
            // pattern in `migrateToVersion11`.
            sqlite3_exec(database, sql, nil, nil, &errorPointer)
        }

        try stampUserVersionUnchecked(16)
    }

    /// v16 → v17: add `generic_constraints` to doc_symbols (#755).
    /// In-place column add. v16 DBs continue to work after the
    /// migration with the new column NULL on every row; the next
    /// `cupertino save --source apple-docs` re-index populates the column from
    /// the AST extractor + signature-column where-clause parsing.
    ///
    /// The trailing `stampUserVersionUnchecked(17)` is load-bearing
    /// per #749. See `migrateToVersion16` for the rationale.
    func migrateToVersion17() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let statements = [
            "ALTER TABLE doc_symbols ADD COLUMN generic_constraints TEXT;",
            "CREATE INDEX IF NOT EXISTS idx_doc_symbols_generic_constraints ON doc_symbols(generic_constraints);",
        ]

        for sql in statements {
            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }
            // Ignore error if column/index already exists, idempotent
            // across partial runs, same pattern as migrateToVersion16.
            sqlite3_exec(database, sql, nil, nil, &errorPointer)
        }

        try stampUserVersionUnchecked(17)
    }

    /// v17 -> v18: DROP `packages` and `package_dependencies` from
    /// search.db (#789). The canonical packages store is `packages.db`
    /// (built by `cupertino save --source packages`, queried by
    /// `cupertino package-search`). The in-search.db tables were a
    /// shallow duplicate fed from a slimmed-to-empty bundled catalog
    /// and added zero value over packages.db.
    ///
    /// Idempotent via `DROP TABLE IF EXISTS`. Indexes drop along with
    /// the parent tables in sqlite.
    ///
    /// Trailing `stampUserVersionUnchecked(18)` is load-bearing per
    /// #749. See `migrateToVersion16` for the rationale.
    func migrateToVersion18() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let statements = [
            "DROP TABLE IF EXISTS package_dependencies;",
            "DROP TABLE IF EXISTS packages;",
        ]

        for sql in statements {
            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }
            sqlite3_exec(database, sql, nil, nil, &errorPointer)
        }

        try stampUserVersionUnchecked(18)
    }

    /// v10 → v11: adds `kind` + `symbols` columns to `docs_metadata`
    /// (#192 C1 doc-kind taxonomy).
    ///
    /// Trailing `stampUserVersionUnchecked(11)` is load-bearing per
    /// #749. See `migrateToVersion16` for the rationale.
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

        try stampUserVersionUnchecked(11)
    }

    /// v9 → v10: adds `synonyms` column to `framework_aliases`.
    ///
    /// Trailing `stampUserVersionUnchecked(10)` is load-bearing per
    /// #749. See `migrateToVersion16` for the rationale.
    func migrateToVersion10() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = "ALTER TABLE framework_aliases ADD COLUMN synonyms TEXT;"

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        // Ignore error if column already exists.
        sqlite3_exec(database, sql, nil, nil, &errorPointer)

        try stampUserVersionUnchecked(10)
    }

    /// v6 → v7: adds 5 platform availability columns to
    /// `sample_code_metadata`. Trailing `stampUserVersionUnchecked(7)`
    /// is load-bearing per #749. See `migrateToVersion16`.
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

        try stampUserVersionUnchecked(7)
    }

    /// v5 → v6: adds 5 platform `min_*` columns + `availability_source`
    /// to `docs_metadata` plus matching filtering indexes. Trailing
    /// `stampUserVersionUnchecked(6)` is load-bearing per #749. See
    /// `migrateToVersion16`.
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

        try stampUserVersionUnchecked(6)
    }

    /// v3 → v4: adds `source` column to `docs_metadata`. Note: this
    /// migrator is a dead-path today — checkAndMigrateSchema's
    /// `currentVersion < 5` branch immediately throws
    /// schemaVersionMismatch right after this migrator runs, because
    /// FTS5 tables cannot be altered and the docs_fts schema changed
    /// at v5. Users on v3 cannot upgrade in-place; they must re-save.
    ///
    /// Trailing `stampUserVersionUnchecked(4)` is included for
    /// consistency with the class-of-bug fix (#749) and as a
    /// future-proof: if v4→v5 ever becomes recoverable, the v3→v4
    /// stamp is already correct.
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

        try stampUserVersionUnchecked(4)
    }

    /// v2 → v3: adds `json_data` column to `docs_metadata`. Trailing
    /// `stampUserVersionUnchecked(3)` is load-bearing per #749. See
    /// `migrateToVersion16`.
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

        try stampUserVersionUnchecked(3)
    }
}
