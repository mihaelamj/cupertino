import Foundation
import Shared
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
            throw SearchError.databaseNotInitialized
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
            throw SearchError.sqliteError("Failed to set schema version: \(errorMessage)")
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
            throw SearchError.sqliteError(
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
            throw SearchError.sqliteError(
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
            throw SearchError.sqliteError(
                "Database schema version \(currentVersion) requires migration to version 12. " +
                    "This is a breaking change that adds AST-derived symbols to the FTS index. " +
                    "Please delete the database and run 'cupertino save' to rebuild: " +
                    "rm \(dbPath.path) && cupertino save"
            )
        }

        if currentVersion < 13 {
            // Version 12 -> 13: URL case canonicalization (#283). Pre-#283
            // `URLUtilities.filename(_:)` derived its 8-hex disambiguator hash
            // from the raw, case-preserving URL string, so URLs differing only
            // in case (e.g. `/documentation/Swift/withTaskGroup(...)` vs the
            // all-lowercase variant) produced two distinct URIs in
            // `docs_metadata` for the same Apple page. The shipped v1.0.0 /
            // v1.0.1 search.db carries ~61k case-axis duplicate clusters
            // covering ~122k rows. Recompute each URI through the post-#283
            // filename helper, merge collisions by latest `last_crawled`, and
            // rename survivors in place.
            try await migrateToVersion13()
        }
    }

    /// v12 -> v13: URL case canonicalization (#283). See `checkAndMigrateSchema`
    /// for the bug background. Algorithm:
    ///   1. Walk `docs_metadata` once, recompute each URI through the post-#283
    ///      `URLUtilities.filename(_:)`. Build the `(oldURI -> newURI)` map in
    ///      memory; rows whose URI is already canonical are skipped.
    ///   2. Group prospective renames by `newURI`. For each group with more
    ///      than one source row (or where the canonical URI already exists in
    ///      `docs_metadata` from a separately-crawled lowercase variant), pick
    ///      the survivor by max `last_crawled` and mark the rest as losers.
    ///   3. Inside one transaction with FK off (so we can rename PK values
    ///      across `docs_metadata`, `docs_structured`, and the dependent
    ///      tables without tripping `ON DELETE CASCADE`):
    ///        - DELETE loser rows from `docs_metadata` (CASCADE drops
    ///          `docs_structured`, `doc_symbols`, `doc_imports`).
    ///        - DELETE loser rows from `doc_code_examples` (FK lacks CASCADE)
    ///          and from `docs_fts` (FTS5 isn't FK-aware).
    ///        - UPDATE survivor URIs across `docs_metadata`, `docs_structured`,
    ///          `docs_fts`, `doc_symbols`, `doc_imports`, `doc_code_examples`.
    ///   4. COMMIT, re-enable FK.
    ///
    /// On any error the transaction rolls back and the function rethrows;
    /// the caller (`checkAndMigrateSchema`) will surface a `SearchError` and
    /// the user can fall back to `rm search.db && cupertino setup`.
    func migrateToVersion13() async throws {
        guard let database else {
            throw SearchError.databaseNotInitialized
        }

        let plan = try v13BuildRenamePlan()

        if plan.renames.isEmpty, plan.deletions.isEmpty {
            // DB is already canonical (e.g. v13-clean bundle, or DB built by a
            // post-#283 binary that never carried case-variant URIs).
            return
        }

        try v13Execute(plan: plan, on: database)
    }

    // MARK: - v13 helpers (URI canonicalization)

    /// One row of pre-migration metadata used to compute the v13 rename plan.
    struct V13MetadataRow: Hashable {
        let uri: String
        let framework: String
        let url: String
        let lastCrawled: Int64
    }

    /// The set of URI rewrites + deletions implied by recomputing filenames
    /// for every row in `docs_metadata`. Built before the transaction starts so
    /// the actual SQL phase is short.
    struct V13RenamePlan {
        /// Survivors whose URI changes. Old URI -> new URI. Each new URI is
        /// guaranteed to be unique within `renames` and to not collide with any
        /// pre-existing untouched row in `docs_metadata`.
        var renames: [String: String]

        /// URIs to drop entirely: case-variant rows that lost the merge to a
        /// peer with a newer `last_crawled` (or to a row whose URI was already
        /// canonical pre-migration).
        var deletions: Set<String>
    }

    /// Walks `docs_metadata` once, computes the post-#283 URI for every row,
    /// and returns the rename + deletion plan.
    ///
    /// Public-internal so unit tests can drive it against a fixture DB without
    /// going through the full `Search.Index.init` -> `checkAndMigrateSchema`
    /// path.
    func v13BuildRenamePlan() throws -> V13RenamePlan {
        guard let database else {
            throw SearchError.databaseNotInitialized
        }

        let rows = try v13ReadMetadataRows(from: database)
        return Self.v13PlanRenames(from: rows)
    }

    /// Pure planning function: given the pre-migration row set, decide which
    /// URIs survive (with what new key) and which get dropped. Side-effect
    /// free; lives on `Self` so tests can call it without an open database.
    static func v13PlanRenames(from rows: [V13MetadataRow]) -> V13RenamePlan {
        // Compute newURI for every row; remember the rows that need any change.
        struct CandidateRename { let row: V13MetadataRow; let newURI: String }
        var candidates: [CandidateRename] = []
        candidates.reserveCapacity(rows.count)

        // Index original URIs so we can detect "the new URI is already taken
        // by a row we wouldn't otherwise have touched".
        var existingURIs = Set<String>(minimumCapacity: rows.count)
        for row in rows {
            existingURIs.insert(row.uri)
        }

        for row in rows {
            guard let url = URL(string: row.url) else { continue }
            let newFilename = URLUtilities.filename(from: url)
            let newURI = "apple-docs://\(row.framework)/\(newFilename)"
            if newURI != row.uri {
                candidates.append(CandidateRename(row: row, newURI: newURI))
            }
        }

        // Group prospective renames by their target URI. For each cluster, the
        // survivor is the row with the highest `last_crawled`. If a row with
        // the canonical URI already exists in `docs_metadata` (i.e. some other
        // crawl of the same Apple page happened to land on the canonical
        // casing), every prospective rename for that URI becomes a deletion;
        // the existing canonical row stays untouched.
        let grouped = Dictionary(grouping: candidates, by: \.newURI)

        var renames: [String: String] = [:]
        var deletions: Set<String> = []

        for (newURI, group) in grouped {
            // Sort newest-first so the survivor (if any) is at index 0.
            let sorted = group.sorted { $0.row.lastCrawled > $1.row.lastCrawled }

            // If a row already lives at newURI in the original `docs_metadata`
            // table (and isn't itself a member of this group, which it can't
            // be since group members all have row.uri != newURI by construction),
            // every group member loses to it.
            if existingURIs.contains(newURI) {
                for candidate in sorted {
                    deletions.insert(candidate.row.uri)
                }
                continue
            }

            // Otherwise the newest member becomes the survivor.
            renames[sorted[0].row.uri] = newURI
            for candidate in sorted.dropFirst() {
                deletions.insert(candidate.row.uri)
            }
        }

        return V13RenamePlan(renames: renames, deletions: deletions)
    }

    /// Read `(uri, framework, url, last_crawled)` for every row in
    /// `docs_metadata`. The migration only needs these four fields; `url` is
    /// what changes the new URI, `framework` is part of the URI namespace,
    /// `last_crawled` breaks ties on collision.
    private func v13ReadMetadataRows(from db: OpaquePointer) throws -> [V13MetadataRow] {
        let sql = "SELECT uri, framework, json_extract(json_data, '$.url'), last_crawled FROM docs_metadata;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            // Fall back to a structured-table read if `json_data` is missing or
            // unparseable on this row set; the v13 migration runs against any
            // DB at v12, where `json_data` is required by schema (since v3).
            throw SearchError.sqliteError(
                "v13 migration: failed to prepare metadata read: \(String(cString: sqlite3_errmsg(db)))"
            )
        }

        var rows: [V13MetadataRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let uri = String(cString: sqlite3_column_text(statement, 0))
            let framework = String(cString: sqlite3_column_text(statement, 1))
            // `json_extract` returns NULL if the path doesn't resolve; skip
            // rows where we can't recover the URL (those rows can't be
            // canonicalized and stay where they are).
            guard let urlPtr = sqlite3_column_text(statement, 2) else { continue }
            let url = String(cString: urlPtr)
            let lastCrawled = sqlite3_column_int64(statement, 3)
            rows.append(V13MetadataRow(uri: uri, framework: framework, url: url, lastCrawled: lastCrawled))
        }

        return rows
    }

    /// Apply the rename + deletion plan inside a single transaction.
    ///
    /// FK is temporarily disabled so we can UPDATE primary keys (`docs_metadata.uri`)
    /// and the dependent FK columns in the same transaction. SQLite re-enforces
    /// FKs on the next `PRAGMA foreign_keys = ON`; `PRAGMA foreign_key_check`
    /// before COMMIT would catch any stragglers if we missed a child table.
    ///
    /// Performance: every SQL statement used in the loops is prepared once at
    /// the top of the method and reused via `sqlite3_reset` + new bindings on
    /// each iteration. A naive prepare-per-statement version was tried first
    /// and ran 60+ minutes against a 405k-row corpus on M-series hardware
    /// (the prepare step parses + plans on every call); the reuse version
    /// targets sub-2-minute completion against the same corpus.
    func v13Execute(plan: V13RenamePlan, on db: OpaquePointer) throws {
        // Speed PRAGMAs for the migration. Both are intentionally unsafe by
        // production standards: `journal_mode = MEMORY` keeps the rollback
        // journal in RAM (so a process crash mid-transaction leaves the DB
        // inconsistent with no on-disk recovery), and `synchronous = OFF`
        // skips fsync after writes (so a power loss mid-transaction can
        // corrupt). Both are acceptable here because (a) the entire migration
        // is one transaction with explicit COMMIT at the end (so on a clean
        // crash the in-memory journal still rolls back the user-visible
        // state), (b) the v13 migration is a one-shot data-correctness pass
        // that the bundled DB ships pre-migrated for, and (c) for live
        // upgrades the user keeps a rollback path via `cupertino setup`
        // re-downloading the bundle if anything goes wrong. Together these
        // give 5-10x speedup on the bulk-DML phase against a 405k-row corpus.
        // Both PRAGMAs must be set OUTSIDE any transaction.
        try v13Exec(db, "PRAGMA journal_mode = MEMORY;")
        try v13Exec(db, "PRAGMA synchronous = OFF;")

        try v13Exec(db, "BEGIN IMMEDIATE TRANSACTION;")
        try v13Exec(db, "PRAGMA foreign_keys = OFF;")

        do {
            // Phase 1: drop loser rows. Order matters because `docs_fts` and
            // `doc_code_examples` are not on the CASCADE chain; drop them
            // before docs_metadata so we never leave orphan FTS / code-example
            // rows behind even if a later DELETE failed.
            let deleteFTS = try v13Prepare(db, "DELETE FROM docs_fts WHERE uri = ?;")
            defer { sqlite3_finalize(deleteFTS) }
            let deleteCode = try v13Prepare(db, "DELETE FROM doc_code_examples WHERE doc_uri = ?;")
            defer { sqlite3_finalize(deleteCode) }
            let deleteMeta = try v13Prepare(db, "DELETE FROM docs_metadata WHERE uri = ?;")
            defer { sqlite3_finalize(deleteMeta) }

            for loser in plan.deletions {
                try v13Run(deleteFTS, text: loser)
                try v13Run(deleteCode, text: loser)
                try v13Run(deleteMeta, text: loser)
                // CASCADE: docs_structured, doc_symbols, doc_imports.
            }

            // Phase 2: rename survivors. Each rename touches every table that
            // carries the URI as either PK or FK column. The order here is
            // arbitrary because FK is off; we follow PK -> structured -> FTS
            // -> child rows for readability.
            let updateMeta = try v13Prepare(db, "UPDATE docs_metadata SET uri = ? WHERE uri = ?;")
            defer { sqlite3_finalize(updateMeta) }
            let updateStruct = try v13Prepare(db, "UPDATE docs_structured SET uri = ? WHERE uri = ?;")
            defer { sqlite3_finalize(updateStruct) }
            let updateFTS = try v13Prepare(db, "UPDATE docs_fts SET uri = ? WHERE uri = ?;")
            defer { sqlite3_finalize(updateFTS) }
            let updateSyms = try v13Prepare(db, "UPDATE doc_symbols SET doc_uri = ? WHERE doc_uri = ?;")
            defer { sqlite3_finalize(updateSyms) }
            let updateImports = try v13Prepare(db, "UPDATE doc_imports SET doc_uri = ? WHERE doc_uri = ?;")
            defer { sqlite3_finalize(updateImports) }
            let updateCode = try v13Prepare(db, "UPDATE doc_code_examples SET doc_uri = ? WHERE doc_uri = ?;")
            defer { sqlite3_finalize(updateCode) }

            for (oldURI, newURI) in plan.renames {
                try v13Run(updateMeta, text: newURI, text2: oldURI)
                try v13Run(updateStruct, text: newURI, text2: oldURI)
                try v13Run(updateFTS, text: newURI, text2: oldURI)
                try v13Run(updateSyms, text: newURI, text2: oldURI)
                try v13Run(updateImports, text: newURI, text2: oldURI)
                try v13Run(updateCode, text: newURI, text2: oldURI)
            }

            try v13Exec(db, "PRAGMA foreign_keys = ON;")
            try v13Exec(db, "COMMIT;")
        } catch {
            // Best-effort rollback; ignore secondary failures since we're
            // already throwing.
            _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            _ = sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
            throw error
        }
    }

    // MARK: - Tiny SQL helpers, scoped to v13

    /// Execute a single statement with no bindings. Throws on any non-OK
    /// result.
    private func v13Exec(_ db: OpaquePointer, _ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let msg = errorPointer.map { String(cString: $0) } ?? "unknown sqlite error"
            throw SearchError.sqliteError("v13 migration: '\(sql)' failed: \(msg)")
        }
    }

    /// Prepare a statement once for reuse. Caller is responsible for calling
    /// `sqlite3_finalize` (typically via `defer`).
    private func v13Prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchError.sqliteError(
                "v13 migration: prepare '\(sql)' failed: \(String(cString: sqlite3_errmsg(db)))"
            )
        }
        return statement
    }

    /// Reset + rebind + step a previously-prepared statement. `text2` is
    /// optional so single-binding DELETEs and two-binding UPDATEs share a code
    /// path. After step, the statement is reset (not finalized) so the next
    /// call can reuse it cheaply.
    private func v13Run(_ statement: OpaquePointer?, text: String, text2: String? = nil) throws {
        // Reset clears any prior result state but keeps the prepared plan; it
        // also clears bindings. SQLITE_TRANSIENT (-1) tells SQLite to make its
        // own copy of the string, so we don't need to keep `text` alive past
        // `sqlite3_step`.
        sqlite3_reset(statement)
        let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, text, -1, transient)
        if let text2 {
            sqlite3_bind_text(statement, 2, text2, -1, transient)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SearchError.sqliteError(
                "v13 migration: step failed: \(String(cString: sqlite3_errmsg(sqlite3_db_handle(statement))))"
            )
        }
    }

    func migrateToVersion11() async throws {
        guard let database else {
            throw SearchError.databaseNotInitialized
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
            throw SearchError.databaseNotInitialized
        }

        let sql = "ALTER TABLE framework_aliases ADD COLUMN synonyms TEXT;"

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        // Ignore error if column already exists
        sqlite3_exec(database, sql, nil, nil, &errorPointer)
    }

    func migrateToVersion7() async throws {
        guard let database else {
            throw SearchError.databaseNotInitialized
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
            throw SearchError.databaseNotInitialized
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
            throw SearchError.databaseNotInitialized
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
            throw SearchError.databaseNotInitialized
        }

        // Add json_data column if it doesn't exist
        let sql = "ALTER TABLE docs_metadata ADD COLUMN json_data TEXT;"
        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        // This will fail silently if column already exists, which is fine
        _ = sqlite3_exec(database, sql, nil, nil, &errorPointer)
    }
}
