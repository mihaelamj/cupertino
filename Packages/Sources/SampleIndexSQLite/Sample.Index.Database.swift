import ASTIndexer
import Foundation
import LoggingModels
import SampleIndexModels
import SearchModels
import SharedConstants
import SQLite3

// MARK: - Sample Index Database

// #673 Phase D iter-5: file_length stays as the only remaining
// file-level blanket (1230 lines, can't be made per-declaration).
// Per-type and per-function disables are scoped below.
// swiftlint:disable file_length

extension Sample.Index {
    /// SQLite FTS5-based database for sample code indexing and search
    ///
    /// #673 Phase D iter-5: 906-line actor body — single owner of the
    /// FTS5 + AST + per-sample availability schema; every CRUD path
    /// + every query path lives here so the SQL stays in one place.
    // swiftlint:disable:next type_body_length
    public actor Database {
        /// Current schema version
        /// Version history:
        /// - 1: Initial schema (projects, files, projects_fts, files_fts)
        /// - 2: Added file_symbols, file_imports tables for SwiftSyntax AST indexing (#81)
        /// Bumped to 3 in #228 phase 2: added per-sample availability
        /// columns to `projects` (`min_ios`, `min_macos`, `min_tvos`,
        /// `min_watchos`, `min_visionos`, `availability_source`) plus
        /// `available_attrs_json` on `files`. No migration — `save
        /// --samples` always wipes the DB and rebuilds, so existing v2
        /// databases get replaced wholesale on the next run.
        public static let schemaVersion: Int32 = 4

        private var database: OpaquePointer?
        private let dbPath: URL
        private var isInitialized = false
        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        public init(
            dbPath: URL,
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

            // #1037: schema-version tracking moved off `PRAGMA user_version`
            // onto a per-pipeline `samples_schema_version` table. The
            // motivation is the one-DB samples collapse: when
            // Sample.Index.Database and Search.Index share a file (target
            // state of #1037), the SQLite file-level `user_version` can
            // hold only one stamp, so the two pipelines would trample each
            // other's version. The new `samples_schema_version` table is
            // a regular table holding a single row with our pipeline's
            // version; Search.Index reads/writes its own state and
            // ignores ours.
            //
            // #228 phase 2: samples.db is wipe-and-rebuild on schema
            // change (no ALTER migrations). But the wipe MUST be
            // conditional on the file actually being a samples DB; the
            // post-#1037 shared-file world has Search.Index creating
            // its own tables in the same file, and a blind wipe would
            // destroy them. The new wipe condition is therefore:
            //   - the file exists on disk, AND
            //   - a Sample.Index table (`projects`) is present (so this
            //     IS a samples DB or a shared file that already carries
            //     samples data), AND
            //   - the samples schema version we read from the file
            //     differs from our compiled schemaVersion
            // When `projects` is absent the file is either fresh OR
            // a shared file Search.Index seeded with its own tables
            // first; in both cases we treat it as a fresh-create-our-
            // tables path with no wipe.
            try await openDatabase()
            if FileManager.default.fileExists(atPath: dbPath.path),
               try await projectsTableExists(),
               try await readSchemaVersion() != Self.schemaVersion {
                disconnect()
                try? FileManager.default.removeItem(at: dbPath)
                try await openDatabase()
            }
            try await createTables()
            try await migrateUserVersionStampIfNeeded()
            try await setSchemaVersion()
            isInitialized = true
        }

        /// Check whether the `projects` table exists in the open DB.
        /// Used by `init` to distinguish "this is a samples DB" (wipe
        /// allowed on version mismatch) from "this file has no samples
        /// data yet" (wipe forbidden because the file may carry tables
        /// owned by another pipeline, see #1037).
        private func projectsTableExists() async throws -> Bool {
            guard let database else { return false }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='projects' LIMIT 1"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return false
            }
            return sqlite3_step(statement) == SQLITE_ROW
        }

        /// Read this pipeline's schema version from the open DB. Reads
        /// from `samples_schema_version` (post-#1037) if that table
        /// exists; otherwise falls back to `PRAGMA user_version`
        /// (pre-#1037 stamping path, kept for backward compatibility
        /// with user samples.db files built by older binaries). Returns
        /// `0` when neither is present (fresh DB).
        private func readSchemaVersion() async throws -> Int32 {
            guard let database else { return 0 }
            // Try the new tracking table first.
            var stmt: OpaquePointer?
            let select = "SELECT version FROM samples_schema_version LIMIT 1"
            if sqlite3_prepare_v2(database, select, -1, &stmt, nil) == SQLITE_OK,
               sqlite3_step(stmt) == SQLITE_ROW {
                let version = sqlite3_column_int(stmt, 0)
                sqlite3_finalize(stmt)
                return version
            }
            sqlite3_finalize(stmt)
            // Fallback: legacy PRAGMA user_version stamp on existing
            // samples.db files written by pre-#1037 cupertino binaries.
            // Returns 0 on a fresh DB.
            return try await readUserVersion()
        }

        /// Read `PRAGMA user_version`. Kept as a private helper for the
        /// pre-#1037 legacy-stamp fallback in `readSchemaVersion()` and
        /// for `migrateUserVersionStampIfNeeded()`'s one-time copy of
        /// the legacy stamp into `samples_schema_version`. Returns `0`
        /// when the DB is freshly created (SQLite's default).
        private func readUserVersion() async throws -> Int32 {
            guard let database else { return 0 }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW
            else { return 0 }
            return sqlite3_column_int(statement, 0)
        }

        /// One-time migration: existing user samples.db files built by
        /// pre-#1037 binaries carry `PRAGMA user_version = 4` (or
        /// whichever historical version) but no
        /// `samples_schema_version` table. On first open by a post-#1037
        /// binary, after `createTables` runs (which creates the new
        /// table), populate the new table from the legacy PRAGMA if and
        /// only if the new table is empty AND the PRAGMA is non-zero.
        /// Idempotent on every subsequent open (the new table is no
        /// longer empty after the first run).
        private func migrateUserVersionStampIfNeeded() async throws {
            guard let database else { return }
            // Is samples_schema_version empty?
            var stmt: OpaquePointer?
            let countSQL = "SELECT COUNT(*) FROM samples_schema_version"
            guard sqlite3_prepare_v2(database, countSQL, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                sqlite3_finalize(stmt)
                return
            }
            let rowCount = sqlite3_column_int(stmt, 0)
            sqlite3_finalize(stmt)
            guard rowCount == 0 else { return }
            // Empty new table. Read legacy PRAGMA; if non-zero, copy it.
            let legacyVersion = try await readUserVersion()
            guard legacyVersion > 0 else { return }
            let sql = "INSERT INTO samples_schema_version (version) VALUES (\(legacyVersion))"
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw Sample.Index.Error.sqliteError(
                    "Failed to migrate legacy PRAGMA user_version=\(legacyVersion) " +
                        "into samples_schema_version: \(errorMessage)"
                )
            }
        }

        /// Close database connection
        public func disconnect() {
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
        }

        /// Inspect `PRAGMA synchronous` on the actor's own connection
        /// (0..3, matching SQLite's enum: 0=OFF, 1=NORMAL, 2=FULL,
        /// 3=EXTRA). Per-connection; not header-persistent. Test-facing.
        public func currentSynchronousMode() -> Int32? {
            guard let database else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, "PRAGMA synchronous;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int(stmt, 0)
        }

        /// Inspect `PRAGMA journal_size_limit` on the actor's own
        /// connection (bytes, -1 = unlimited). Per-connection.
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

        // MARK: - Database Setup

        private func openDatabase() async throws {
            var dbPointer: OpaquePointer?

            guard sqlite3_open(dbPath.path, &dbPointer) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                sqlite3_close(dbPointer)
                throw Sample.Index.Error.sqliteError("Failed to open database: \(errorMessage)")
            }

            // #236: WAL journal mode lets readers (`cupertino read-sample`,
            // `cupertino list-samples`, `cupertino doctor`) proceed while
            // a `cupertino save --samples` writer holds the DB. PRAGMA is
            // idempotent and persists in the file header. Log and
            // continue on failure.
            if sqlite3_exec(dbPointer, "PRAGMA journal_mode = WAL", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to enable WAL on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .samples
                )
            }

            // #236 follow-up: SQLite-recommended `synchronous=NORMAL`
            // paired with WAL. Per-connection. See
            // https://www.sqlite.org/pragma.html#pragma_synchronous.
            if sqlite3_exec(dbPointer, "PRAGMA synchronous = NORMAL", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to set synchronous=NORMAL on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .samples
                )
            }

            // #236 follow-up: cap the WAL sidecar at 64 MB so
            // pathological reader-starvation cases don't grow the
            // file without bound. Default is -1 (unlimited).
            if sqlite3_exec(dbPointer, "PRAGMA journal_size_limit = 67108864", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to set journal_size_limit on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .samples
                )
            }

            database = dbPointer
        }

        /// Stamp this pipeline's schema version into the
        /// `samples_schema_version` table. Post-#1037 we no longer write
        /// `PRAGMA user_version` from this pipeline: the per-file
        /// `user_version` is a shared SQLite header byte that the
        /// Search.Index pipeline also stamps, and once the two pipelines
        /// share a file (target state of #1037) blind PRAGMA writes
        /// would trample each other. The single-row `samples_schema_version`
        /// table is per-pipeline state and never collides with other
        /// pipelines' tables in the same file.
        ///
        /// Idempotent via `INSERT OR REPLACE`. The first call on a
        /// fresh DB inserts the row; subsequent calls overwrite it with
        /// the current `schemaVersion`. The table itself is created in
        /// `createTables`; this method is always called after
        /// `createTables` in `init`.
        private func setSchemaVersion() async throws {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = "INSERT OR REPLACE INTO samples_schema_version (id, version) VALUES (1, \(Self.schemaVersion))"
            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }

            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
                throw Sample.Index.Error.sqliteError("Failed to set schema version: \(errorMessage)")
            }
        }

        // #673 Phase D iter-5: 129-line body — full DDL for the FTS5
        // virtual tables + AST tables + indexes; one transaction, one
        // place to maintain the schema source-of-truth.
        // swiftlint:disable:next function_body_length
        private func createTables() async throws {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = """
            -- Per-pipeline schema-version tracking (#1037). Replaces the
            -- file-level `PRAGMA user_version` so this pipeline can share
            -- a SQLite file with Search.Index without trampling each
            -- other's version stamps. Single-row design: id always = 1,
            -- version carries our compiled schemaVersion. Read by
            -- `readSchemaVersion()`, written by `setSchemaVersion()`.
            CREATE TABLE IF NOT EXISTS samples_schema_version (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                version INTEGER NOT NULL
            );

            -- Projects table: metadata about each sample project
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                frameworks TEXT NOT NULL,
                readme TEXT,
                web_url TEXT NOT NULL,
                zip_filename TEXT NOT NULL,
                file_count INTEGER NOT NULL,
                total_size INTEGER NOT NULL,
                indexed_at INTEGER NOT NULL,
                -- Availability columns (#228 phase 2). Source = "sample-swift"
                -- when populated from the per-sample availability.json sidecar
                -- written during indexing; NULL when the sample shipped no
                -- Package.swift platforms block.
                min_ios TEXT,
                min_macos TEXT,
                min_tvos TEXT,
                min_watchos TEXT,
                min_visionos TEXT,
                availability_source TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_projects_title ON projects(title);
            CREATE INDEX IF NOT EXISTS idx_projects_min_ios ON projects(min_ios);
            CREATE INDEX IF NOT EXISTS idx_projects_min_macos ON projects(min_macos);
            CREATE INDEX IF NOT EXISTS idx_projects_min_tvos ON projects(min_tvos);
            CREATE INDEX IF NOT EXISTS idx_projects_min_watchos ON projects(min_watchos);
            CREATE INDEX IF NOT EXISTS idx_projects_min_visionos ON projects(min_visionos);

            -- FTS5 for project search (title, description, readme)
            CREATE VIRTUAL TABLE IF NOT EXISTS projects_fts USING fts5(
                id,
                title,
                description,
                readme,
                frameworks,
                tokenize='porter unicode61'
            );

            -- Files table: individual source files
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_id TEXT NOT NULL,
                path TEXT NOT NULL,
                filename TEXT NOT NULL,
                folder TEXT NOT NULL,
                extension TEXT NOT NULL,
                content TEXT NOT NULL,
                size INTEGER NOT NULL,
                -- Per-file @available occurrences as a JSON array of
                -- {line, raw, platforms[]} (#228 phase 2). NULL when the
                -- file had no @available attributes — distinct from
                -- "annotation never ran".
                available_attrs_json TEXT,
                FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
                UNIQUE(project_id, path)
            );

            CREATE INDEX IF NOT EXISTS idx_files_project ON files(project_id);
            CREATE INDEX IF NOT EXISTS idx_files_folder ON files(folder);
            CREATE INDEX IF NOT EXISTS idx_files_extension ON files(extension);

            -- FTS5 for file content search
            CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
                project_id,
                path,
                filename,
                content,
                tokenize='unicode61'
            );

            -- Symbols extracted from Swift files via SwiftSyntax AST (#81)
            CREATE TABLE IF NOT EXISTS file_symbols (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                line INTEGER NOT NULL,
                column INTEGER NOT NULL,
                signature TEXT,
                is_async INTEGER NOT NULL DEFAULT 0,
                is_throws INTEGER NOT NULL DEFAULT 0,
                is_public INTEGER NOT NULL DEFAULT 0,
                is_static INTEGER NOT NULL DEFAULT 0,
                attributes TEXT,
                conformances TEXT,
                generic_params TEXT,
                -- #837 stage 1: authoritative Apple-type generic constraints
                -- written by the postprocessor's samples-apple-constraints
                -- pass. Mirrors search.db's doc_symbols.generic_constraints
                -- column. NULL until the pass runs.
                generic_constraints TEXT,
                -- #837: tracks which enrichment pass version last
                -- annotated this row. NULL until any pass runs.
                enrichment_version INTEGER,
                FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_file_symbols_file ON file_symbols(file_id);
            CREATE INDEX IF NOT EXISTS idx_file_symbols_kind ON file_symbols(kind);
            CREATE INDEX IF NOT EXISTS idx_file_symbols_name ON file_symbols(name);
            CREATE INDEX IF NOT EXISTS idx_file_symbols_async ON file_symbols(is_async);
            CREATE INDEX IF NOT EXISTS idx_file_symbols_enrichment ON file_symbols(enrichment_version);

            -- FTS for symbol name search
            CREATE VIRTUAL TABLE IF NOT EXISTS file_symbols_fts USING fts5(
                name,
                signature,
                attributes,
                conformances,
                tokenize='unicode61'
            );

            -- Imports extracted from Swift files (#81)
            CREATE TABLE IF NOT EXISTS file_imports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_id INTEGER NOT NULL,
                module_name TEXT NOT NULL,
                line INTEGER NOT NULL,
                is_exported INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_file_imports_file ON file_imports(file_id);
            CREATE INDEX IF NOT EXISTS idx_file_imports_module ON file_imports(module_name);
            """

            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }

            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
                throw Sample.Index.Error.sqliteError("Failed to create tables: \(errorMessage)")
            }
        }

        // MARK: - Project Indexing

        /// Index a sample project
        ///
        /// #673 Phase D iter-5: 70-line body — INSERT project row + N
        /// file rows + per-file AST symbols/imports in one transaction.
        // swiftlint:disable:next function_body_length
        public func indexProject(_ project: Project) async throws {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            // Insert into projects table
            let sql = """
            INSERT OR REPLACE INTO projects
            (id, title, description, frameworks, readme, web_url, zip_filename, file_count, total_size, indexed_at,
             min_ios, min_macos, min_tvos, min_watchos, min_visionos, availability_source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw Sample.Index.Error.prepareFailed("Project insert: \(errorMessage)")
            }

            let frameworksString = project.frameworks.joined(separator: ",")

            sqlite3_bind_text(statement, 1, (project.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (project.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (project.description as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (frameworksString as NSString).utf8String, -1, nil)

            if let readme = project.readme {
                sqlite3_bind_text(statement, 5, (readme as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 5)
            }

            sqlite3_bind_text(statement, 6, (project.webURL as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 7, (project.zipFilename as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 8, Int32(project.fileCount))
            sqlite3_bind_int64(statement, 9, Int64(project.totalSize))
            sqlite3_bind_int64(statement, 10, Int64(project.indexedAt.timeIntervalSince1970))

            /// #228 phase 2: availability columns 11-16.
            func bindMin(_ pos: Int32, _ key: String) {
                if let value = project.deploymentTargets[key] {
                    sqlite3_bind_text(statement, pos, (value as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, pos)
                }
            }
            bindMin(11, "iOS")
            bindMin(12, "macOS")
            bindMin(13, "tvOS")
            bindMin(14, "watchOS")
            bindMin(15, "visionOS")
            if let source = project.availabilitySource {
                sqlite3_bind_text(statement, 16, (source as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 16)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw Sample.Index.Error.insertFailed("Project insert: \(errorMessage)")
            }

            // Insert into FTS5
            let ftsSql = """
            INSERT OR REPLACE INTO projects_fts (id, title, description, readme, frameworks)
            VALUES (?, ?, ?, ?, ?);
            """

            var ftsStatement: OpaquePointer?
            defer { sqlite3_finalize(ftsStatement) }

            guard sqlite3_prepare_v2(database, ftsSql, -1, &ftsStatement, nil) == SQLITE_OK else {
                return // FTS insert failure is non-fatal
            }

            sqlite3_bind_text(ftsStatement, 1, (project.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStatement, 2, (project.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStatement, 3, (project.description as NSString).utf8String, -1, nil)

            if let readme = project.readme {
                sqlite3_bind_text(ftsStatement, 4, (readme as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(ftsStatement, 4)
            }

            sqlite3_bind_text(ftsStatement, 5, (frameworksString as NSString).utf8String, -1, nil)

            _ = sqlite3_step(ftsStatement)
        }

        // MARK: - File Indexing

        /// Index a source file
        public func indexFile(_ file: File) async throws {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            // Insert into files table
            let sql = """
            INSERT OR REPLACE INTO files
            (project_id, path, filename, folder, extension, content, size, available_attrs_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw Sample.Index.Error.prepareFailed("File insert: \(errorMessage)")
            }

            sqlite3_bind_text(statement, 1, (file.projectId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (file.path as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (file.filename as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (file.folder as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (file.fileExtension as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (file.content as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 7, Int64(file.size))

            // #228 phase 2: per-file @available occurrences as JSON.
            // NULL when the file had no attributes — distinct from
            // "annotation didn't run".
            if let attrs = file.availableAttrsJSON {
                sqlite3_bind_text(statement, 8, (attrs as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 8)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw Sample.Index.Error.insertFailed("File insert: \(errorMessage)")
            }

            // Insert into FTS5
            let ftsSql = """
            INSERT INTO files_fts (project_id, path, filename, content)
            VALUES (?, ?, ?, ?);
            """

            var ftsStatement: OpaquePointer?
            defer { sqlite3_finalize(ftsStatement) }

            guard sqlite3_prepare_v2(database, ftsSql, -1, &ftsStatement, nil) == SQLITE_OK else {
                return // FTS insert failure is non-fatal
            }

            sqlite3_bind_text(ftsStatement, 1, (file.projectId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStatement, 2, (file.path as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStatement, 3, (file.filename as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStatement, 4, (file.content as NSString).utf8String, -1, nil)

            _ = sqlite3_step(ftsStatement)
        }

        /// Get the file ID for a project/path combination
        public func getFileId(projectId: String, path: String) async throws -> Int64? {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = "SELECT id FROM files WHERE project_id = ? AND path = ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }

            sqlite3_bind_text(statement, 1, (projectId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (path as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            return sqlite3_column_int64(statement, 0)
        }

        // MARK: - Symbol Indexing (#81)

        /// Index symbols extracted from a Swift file
        public func indexSymbols(
            fileId: Int64,
            symbols: [ASTIndexer.Symbol]
        ) async throws {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = """
            INSERT INTO file_symbols
            (file_id, name, kind, line, column, signature, is_async, is_throws,
             is_public, is_static, attributes, conformances, generic_params)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            for symbol in symbols {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }

                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    continue // Skip failed symbols, don't fail entire indexing
                }

                sqlite3_bind_int64(statement, 1, fileId)
                sqlite3_bind_text(statement, 2, (symbol.name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (symbol.kind.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 4, Int32(symbol.line))
                sqlite3_bind_int(statement, 5, Int32(symbol.column))

                if let signature = symbol.signature {
                    sqlite3_bind_text(statement, 6, (signature as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 6)
                }

                sqlite3_bind_int(statement, 7, symbol.isAsync ? 1 : 0)
                sqlite3_bind_int(statement, 8, symbol.isThrows ? 1 : 0)
                sqlite3_bind_int(statement, 9, symbol.isPublic ? 1 : 0)
                sqlite3_bind_int(statement, 10, symbol.isStatic ? 1 : 0)

                let attributesStr = symbol.attributes.isEmpty ? nil : symbol.attributes.joined(separator: ",")
                let conformancesStr = symbol.conformances.isEmpty ? nil : symbol.conformances.joined(separator: ",")
                let genericParamsStr = symbol.genericParameters.isEmpty ? nil : symbol.genericParameters.joined(separator: ",")

                if let attrs = attributesStr {
                    sqlite3_bind_text(statement, 11, (attrs as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 11)
                }

                if let confs = conformancesStr {
                    sqlite3_bind_text(statement, 12, (confs as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 12)
                }

                if let generics = genericParamsStr {
                    sqlite3_bind_text(statement, 13, (generics as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 13)
                }

                _ = sqlite3_step(statement)

                // Insert into FTS
                try await indexSymbolFTS(symbol: symbol)
            }
        }

        /// #837 stage 1 — apply the authoritative Apple-type generic
        /// constraints table over `file_symbols.generic_constraints`.
        ///
        /// Parallels `Search.Index.applyAppleStaticConstraints` for
        /// search.db. Each entry's `docURI` is split to extract the
        /// type name (last URI segment); a symbol whose lowercased
        /// `file_symbols.name` matches that token gets its
        /// `generic_constraints` set to the joined-comma
        /// `entry.constraints` blob. Stamps `enrichment_version` so
        /// idempotency checks can detect already-enriched rows.
        ///
        /// Returns the affected-row count. If `lookup` is nil, returns
        /// 0 without touching the DB.
        public func applyAppleStaticConstraints(
            lookup: (any Search.StaticConstraintsLookup)?,
            enrichmentVersion: Int = 1
        ) async throws -> Int {
            guard let lookup, let database else { return 0 }
            let entries = try await lookup.allEntries()
            guard !entries.isEmpty else { return 0 }

            var nameToConstraints: [String: String] = [:]
            for entry in entries {
                guard let lastSegment = entry.docURI.split(separator: "/").last else { continue }
                let key = String(lastSegment).lowercased()
                let joined = entry.constraints.joined(separator: ",")
                nameToConstraints[key] = joined
            }

            _ = sqlite3_exec(database, "BEGIN TRANSACTION", nil, nil, nil)
            let sql = """
            UPDATE file_symbols
            SET generic_constraints = ?, enrichment_version = ?
            WHERE LOWER(name) = ?;
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                _ = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                throw Sample.Index.Error.sqliteError("prepare applyAppleStaticConstraints UPDATE failed")
            }
            var affected = 0
            for (lower, joined) in nameToConstraints {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_text(statement, 1, (joined as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 2, Int32(enrichmentVersion))
                sqlite3_bind_text(statement, 3, (lower as NSString).utf8String, -1, nil)
                _ = sqlite3_step(statement)
                affected += Int(sqlite3_changes(database))
            }
            _ = sqlite3_exec(database, "COMMIT", nil, nil, nil)
            return affected
        }

        /// Index symbol into FTS table
        private func indexSymbolFTS(symbol: ASTIndexer.Symbol) async throws {
            guard let database else { return }

            let sql = """
            INSERT INTO file_symbols_fts (name, signature, attributes, conformances)
            VALUES (?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return
            }

            sqlite3_bind_text(statement, 1, (symbol.name as NSString).utf8String, -1, nil)

            if let signature = symbol.signature {
                sqlite3_bind_text(statement, 2, (signature as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 2)
            }

            let attributesStr = symbol.attributes.joined(separator: " ")
            let conformancesStr = symbol.conformances.joined(separator: " ")

            sqlite3_bind_text(statement, 3, (attributesStr as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (conformancesStr as NSString).utf8String, -1, nil)

            _ = sqlite3_step(statement)
        }

        /// Index imports extracted from a Swift file
        public func indexImports(
            fileId: Int64,
            imports: [ASTIndexer.Import]
        ) async throws {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = """
            INSERT INTO file_imports (file_id, module_name, line, is_exported)
            VALUES (?, ?, ?, ?);
            """

            for imp in imports {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }

                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    continue
                }

                sqlite3_bind_int64(statement, 1, fileId)
                sqlite3_bind_text(statement, 2, (imp.moduleName as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 3, Int32(imp.line))
                sqlite3_bind_int(statement, 4, imp.isExported ? 1 : 0)

                _ = sqlite3_step(statement)
            }
        }

        // MARK: - Search Projects

        /// Search projects by query
        ///
        /// #673 Phase D iter-5: 61-line body — FTS5 MATCH + framework
        /// filter + row hydration into Project structs.
        ///
        /// #732 expansion: optional 5-field platform filter. When any
        /// `min<Platform>` is non-nil, the SQL grows an
        /// `AND p.min_<platform> IS NOT NULL AND p.min_<platform> <= ?`
        /// clause for each set parameter. Multiple set parameters are
        /// AND-combined — a project must satisfy every requested
        /// minimum to pass (a sample that runs on iOS 15+ AND macOS 12+
        /// is included when the user asks for iOS 17+ AND macOS 14+).
        /// Lex compare matches the existing convention used in #220's
        /// `Search.PackageQuery` + #233's `searchFiles`.
        // swiftlint:disable:next function_body_length
        public func searchProjects(
            query: String,
            framework: String? = nil,
            limit: Int = 20,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) async throws -> [Project] {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw Sample.Index.Error.invalidQuery("Query cannot be empty")
            }

            // Build FTS5 query: tokenize natural language, drop
            // stopwords, OR-join the remainder. Same shape as
            // Search.PackageQuery uses for packages.db (#238 unified
            // both paths via Shared.Utils.FTSQuery).
            let sanitizedQuery = Shared.Utils.FTSQuery.build(question: query)
            guard !sanitizedQuery.isEmpty else { return [] }

            // #732 — collect the per-platform filters into an ordered
            // (column, value) list so the SQL clause + parameter binds
            // stay in lock-step. Iterated twice: once to build the
            // clauses, once to bind. Empty list short-circuits both.
            let platformFilters: [(column: String, value: String)] = [
                ("min_ios", minIOS),
                ("min_macos", minMacOS),
                ("min_tvos", minTvOS),
                ("min_watchos", minWatchOS),
                ("min_visionos", minVisionOS),
            ].compactMap { column, value in
                guard let value else { return nil }
                return (column, value)
            }

            var sql = """
            SELECT p.id, p.title, p.description, p.frameworks, p.readme,
                   p.web_url, p.zip_filename, p.file_count, p.total_size, p.indexed_at
            FROM projects p
            JOIN projects_fts f ON p.id = f.id
            WHERE projects_fts MATCH ?
            """

            if framework != nil {
                sql += " AND p.frameworks LIKE ?"
            }

            for filter in platformFilters {
                sql += " AND p.\(filter.column) IS NOT NULL AND p.\(filter.column) <= ?"
            }

            sql += " ORDER BY bm25(projects_fts) LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw Sample.Index.Error.searchFailed("Project search: \(errorMessage)")
            }

            var paramIndex: Int32 = 1
            sqlite3_bind_text(statement, paramIndex, (sanitizedQuery as NSString).utf8String, -1, nil)
            paramIndex += 1

            if let framework {
                let pattern = "%\(framework.lowercased())%"
                sqlite3_bind_text(statement, paramIndex, (pattern as NSString).utf8String, -1, nil)
                paramIndex += 1
            }

            for filter in platformFilters {
                sqlite3_bind_text(statement, paramIndex, (filter.value as NSString).utf8String, -1, nil)
                paramIndex += 1
            }

            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [Project] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(statement, 0),
                      let titlePtr = sqlite3_column_text(statement, 1),
                      let descPtr = sqlite3_column_text(statement, 2),
                      let frameworksPtr = sqlite3_column_text(statement, 3),
                      let webURLPtr = sqlite3_column_text(statement, 5),
                      let zipPtr = sqlite3_column_text(statement, 6)
                else {
                    continue
                }

                let readme = sqlite3_column_text(statement, 4).map { String(cString: $0) }

                let project = Project(
                    id: String(cString: idPtr),
                    title: String(cString: titlePtr),
                    description: String(cString: descPtr),
                    frameworks: String(cString: frameworksPtr).components(separatedBy: ","),
                    readme: readme,
                    webURL: String(cString: webURLPtr),
                    zipFilename: String(cString: zipPtr),
                    fileCount: Int(sqlite3_column_int(statement, 7)),
                    totalSize: Int(sqlite3_column_int64(statement, 8)),
                    indexedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9)))
                )

                results.append(project)
            }

            return results
        }

        // MARK: - Search Files

        // `FileSearchResult` lifted to `Sample.Index.FileSearchResult`
        // in the `SampleIndexModels` target so the
        // `Sample.Index.Reader` protocol can return it without a
        // cyclic dep on `SampleIndex`.

        /// Search files by content
        ///
        /// #673 Phase D iter-5: 74-line body — FTS5 MATCH against files_fts
        /// + project/extension filters + per-row hydration into SampleFile.
        // swiftlint:disable:next function_body_length
        public func searchFiles(
            query: String,
            projectId: String? = nil,
            fileExtension: String? = nil,
            limit: Int = 20,
            platform: String? = nil,
            minVersion: String? = nil
        ) async throws -> [Sample.Index.FileSearchResult] {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw Sample.Index.Error.invalidQuery("Query cannot be empty")
            }

            // Build FTS5 query: tokenize natural language, drop
            // stopwords, OR-join the remainder. Same shape as
            // Search.PackageQuery uses for packages.db (#238 unified
            // both paths via Shared.Utils.FTSQuery).
            let sanitizedQuery = Shared.Utils.FTSQuery.build(question: query)
            guard !sanitizedQuery.isEmpty else { return [] }

            // #233: optional platform filter — JOIN projects table when
            // both `platform` and `minVersion` are set, restrict to rows
            // whose `min_<platform>` column is non-NULL and lex-≤
            // the requested version. Lex compare matches the convention
            // used in #220's PackageQuery.
            let platformColumn: String?
            if platform != nil, minVersion != nil {
                platformColumn = Sample.Index.minColumn(for: platform ?? "")
            } else {
                platformColumn = nil
            }

            var sql = """
            SELECT f.project_id, f.path, f.filename, snippet(files_fts, 3, '<b>', '</b>', '...', 50), bm25(files_fts)
            FROM files f
            JOIN files_fts fts ON f.project_id = fts.project_id AND f.path = fts.path
            """

            if let platformColumn {
                sql += " JOIN projects p ON p.id = f.project_id"
                _ = platformColumn
            }

            sql += " WHERE files_fts MATCH ?"

            if projectId != nil {
                sql += " AND f.project_id = ?"
            }

            if fileExtension != nil {
                sql += " AND f.extension = ?"
            }

            if let platformColumn {
                sql += " AND p.\(platformColumn) IS NOT NULL AND p.\(platformColumn) <= ?"
            }

            sql += " ORDER BY bm25(files_fts) LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw Sample.Index.Error.searchFailed("File search: \(errorMessage)")
            }

            var paramIndex: Int32 = 1
            sqlite3_bind_text(statement, paramIndex, (sanitizedQuery as NSString).utf8String, -1, nil)
            paramIndex += 1

            if let projectId {
                sqlite3_bind_text(statement, paramIndex, (projectId as NSString).utf8String, -1, nil)
                paramIndex += 1
            }

            if let fileExtension {
                sqlite3_bind_text(statement, paramIndex, (fileExtension.lowercased() as NSString).utf8String, -1, nil)
                paramIndex += 1
            }

            if platformColumn != nil, let minVersion {
                sqlite3_bind_text(statement, paramIndex, (minVersion as NSString).utf8String, -1, nil)
                paramIndex += 1
            }

            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [Sample.Index.FileSearchResult] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let projectIdPtr = sqlite3_column_text(statement, 0),
                      let pathPtr = sqlite3_column_text(statement, 1),
                      let filenamePtr = sqlite3_column_text(statement, 2),
                      let snippetPtr = sqlite3_column_text(statement, 3)
                else {
                    continue
                }

                results.append(Sample.Index.FileSearchResult(
                    projectId: String(cString: projectIdPtr),
                    path: String(cString: pathPtr),
                    filename: String(cString: filenamePtr),
                    snippet: String(cString: snippetPtr),
                    rank: sqlite3_column_double(statement, 4)
                ))
            }

            return results
        }

        // MARK: - Get Project

        /// Get a project by ID
        ///
        /// #673 Phase D iter-5: 51-line body — single SELECT + per-row
        /// hydration; just past the 50-line threshold.
        // swiftlint:disable:next function_body_length
        public func getProject(id: String) async throws -> Project? {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = """
            SELECT id, title, description, frameworks, readme, web_url, zip_filename,
                   file_count, total_size, indexed_at,
                   min_ios, min_macos, min_tvos, min_watchos, min_visionos, availability_source
            FROM projects
            WHERE id = ?
            LIMIT 1;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }

            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            guard let idPtr = sqlite3_column_text(statement, 0),
                  let titlePtr = sqlite3_column_text(statement, 1),
                  let descPtr = sqlite3_column_text(statement, 2),
                  let frameworksPtr = sqlite3_column_text(statement, 3),
                  let webURLPtr = sqlite3_column_text(statement, 5),
                  let zipPtr = sqlite3_column_text(statement, 6)
            else {
                return nil
            }

            let readme = sqlite3_column_text(statement, 4).map { String(cString: $0) }

            // #228 phase 2: read availability columns 10..15.
            var deploymentTargets: [String: String] = [:]
            for (idx, key) in [(10, "iOS"), (11, "macOS"), (12, "tvOS"), (13, "watchOS"), (14, "visionOS")] {
                if let cString = sqlite3_column_text(statement, Int32(idx)) {
                    deploymentTargets[key] = String(cString: cString)
                }
            }
            let availabilitySource = sqlite3_column_text(statement, 15).map { String(cString: $0) }

            return Project(
                id: String(cString: idPtr),
                title: String(cString: titlePtr),
                description: String(cString: descPtr),
                frameworks: String(cString: frameworksPtr).components(separatedBy: ","),
                readme: readme,
                webURL: String(cString: webURLPtr),
                zipFilename: String(cString: zipPtr),
                fileCount: Int(sqlite3_column_int(statement, 7)),
                totalSize: Int(sqlite3_column_int64(statement, 8)),
                indexedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9))),
                deploymentTargets: deploymentTargets,
                availabilitySource: availabilitySource
            )
        }

        // MARK: - Get File

        /// Get a file by project ID and path
        public func getFile(projectId: String, path: String) async throws -> File? {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = """
            SELECT project_id, path, filename, folder, extension, content, size, available_attrs_json
            FROM files
            WHERE project_id = ? AND path = ?
            LIMIT 1;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }

            sqlite3_bind_text(statement, 1, (projectId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (path as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            guard let projectIdPtr = sqlite3_column_text(statement, 0),
                  let pathPtr = sqlite3_column_text(statement, 1),
                  let contentPtr = sqlite3_column_text(statement, 5)
            else {
                return nil
            }

            // #228 phase 2: column 7 is available_attrs_json (NULL when
            // the file had no @available occurrences).
            let attrsJSON = sqlite3_column_text(statement, 7).map { String(cString: $0) }

            return File(
                projectId: String(cString: projectIdPtr),
                path: String(cString: pathPtr),
                content: String(cString: contentPtr),
                availableAttrsJSON: attrsJSON
            )
        }

        // MARK: - List Files

        /// List all files in a project
        public func listFiles(projectId: String, folder: String? = nil) async throws -> [File] {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            var sql = """
            SELECT project_id, path, filename, folder, extension, content, size
            FROM files
            WHERE project_id = ?
            """

            if folder != nil {
                sql += " AND folder = ?"
            }

            sql += " ORDER BY path;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            sqlite3_bind_text(statement, 1, (projectId as NSString).utf8String, -1, nil)

            if let folder {
                sqlite3_bind_text(statement, 2, (folder as NSString).utf8String, -1, nil)
            }

            var results: [File] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let projectIdPtr = sqlite3_column_text(statement, 0),
                      let pathPtr = sqlite3_column_text(statement, 1),
                      let contentPtr = sqlite3_column_text(statement, 5)
                else {
                    continue
                }

                results.append(File(
                    projectId: String(cString: projectIdPtr),
                    path: String(cString: pathPtr),
                    content: String(cString: contentPtr)
                ))
            }

            return results
        }

        // MARK: - List Projects

        /// List all projects
        public func listProjects(
            framework: String? = nil,
            limit: Int = 100
        ) async throws -> [Project] {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            var sql = """
            SELECT id, title, description, frameworks, readme, web_url, zip_filename,
                   file_count, total_size, indexed_at
            FROM projects
            """

            if framework != nil {
                sql += " WHERE frameworks LIKE ?"
            }

            sql += " ORDER BY title LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            var paramIndex: Int32 = 1
            if let framework {
                let pattern = "%\(framework.lowercased())%"
                sqlite3_bind_text(statement, paramIndex, (pattern as NSString).utf8String, -1, nil)
                paramIndex += 1
            }

            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [Project] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idPtr = sqlite3_column_text(statement, 0),
                      let titlePtr = sqlite3_column_text(statement, 1),
                      let descPtr = sqlite3_column_text(statement, 2),
                      let frameworksPtr = sqlite3_column_text(statement, 3),
                      let webURLPtr = sqlite3_column_text(statement, 5),
                      let zipPtr = sqlite3_column_text(statement, 6)
                else {
                    continue
                }

                let readme = sqlite3_column_text(statement, 4).map { String(cString: $0) }

                results.append(Project(
                    id: String(cString: idPtr),
                    title: String(cString: titlePtr),
                    description: String(cString: descPtr),
                    frameworks: String(cString: frameworksPtr).components(separatedBy: ","),
                    readme: readme,
                    webURL: String(cString: webURLPtr),
                    zipFilename: String(cString: zipPtr),
                    fileCount: Int(sqlite3_column_int(statement, 7)),
                    totalSize: Int(sqlite3_column_int64(statement, 8)),
                    indexedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9)))
                ))
            }

            return results
        }

        // MARK: - Statistics

        /// Get project count
        public func projectCount() async throws -> Int {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = Shared.Utils.SQL.countRows(in: "projects")

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// Get file count
        public func fileCount() async throws -> Int {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = Shared.Utils.SQL.countRows(in: "files")

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// Get total symbol count (#81)
        public func symbolCount() async throws -> Int {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = Shared.Utils.SQL.countRows(in: "file_symbols")

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// #837 read-side wiring — search `file_symbols` for rows whose
        /// `name`, `attributes`, `conformances`, `signature`, or
        /// `generic_constraints` LIKE-match the query. Returns the set
        /// of composite `"projectId|path"` keys identifying the files
        /// each matching symbol belongs to. Caller
        /// (`Sample.Search.Service`) uses the set to rank-boost
        /// matching `Sample.Index.FileSearchResult` rows in the search
        /// result — same pattern search.db uses in
        /// `Search.Index.searchSymbolsForURIs`.
        ///
        /// JOINs `file_symbols → files` so the caller doesn't have to
        /// round-trip through `getFileId` to identify rows. Composite
        /// key uses `|` as the separator because neither `projectId`
        /// (a slug) nor `path` contains it in any real corpus.
        ///
        /// Fails silently with an empty set when the underlying SQL
        /// can't prepare; symbol search is an optional enhancement,
        /// not a blocker.
        public func searchSymbolsForFiles(query: String, limit: Int) async throws -> Set<String> {
            guard let database else { return [] }
            let cleanQuery = query
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard cleanQuery.count >= 3 else { return [] }
            let likePattern = "%\(cleanQuery)%"
            let sql = """
            SELECT DISTINCT f.project_id || '|' || f.path
            FROM file_symbols s
            JOIN files f ON s.file_id = f.id
            WHERE s.name LIKE ?
               OR s.attributes LIKE ?
               OR s.conformances LIKE ?
               OR s.signature LIKE ?
               OR s.generic_constraints LIKE ?
            LIMIT ?;
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_text(statement, 1, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 6, Int32(limit))
            var keys: Set<String> = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(statement, 0) {
                    keys.insert(String(cString: ptr))
                }
            }
            return keys
        }

        /// #857 cross-DB `search_generics` — return `FileSearchResult`
        /// rows whose `generic_constraints`, `signature`, or `name`
        /// LIKE-matches the constraint token. JOINs through `files` so
        /// the caller has projectId + path + filename without a second
        /// round-trip. Optional `framework` filter matches against the
        /// project's framework column. Returns an empty array on prepare
        /// failure (symbol enrichment is optional, the MCP fan-out should
        /// still merge whatever the other DBs return).
        ///
        /// The snippet text uses the file-symbol's `signature` column
        /// when available, falling back to `name` so the unified renderer
        /// always has a non-empty body to display.
        public func searchFilesByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
        ) async throws -> [Sample.Index.FileSearchResult] {
            guard let database else { return [] }
            let cleaned = constraint
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { return [] }
            let likePattern = "%\(cleaned)%"

            let frameworkClause = framework == nil ? "" : "AND p.framework = ?"
            let sql = """
            SELECT
                f.project_id,
                f.path,
                f.filename,
                COALESCE(NULLIF(s.signature, ''), s.name) AS snippet,
                -1.0 AS rank_value
            FROM file_symbols s
            JOIN files f ON s.file_id = f.id
            JOIN projects p ON f.project_id = p.id
            WHERE (s.generic_constraints LIKE ?
                   OR s.signature LIKE ?
                   OR s.name LIKE ?)
            \(frameworkClause)
            LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }

            sqlite3_bind_text(statement, 1, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (likePattern as NSString).utf8String, -1, nil)
            var bindIdx: Int32 = 4
            if let framework {
                sqlite3_bind_text(statement, bindIdx, (framework as NSString).utf8String, -1, nil)
                bindIdx += 1
            }
            sqlite3_bind_int(statement, bindIdx, Int32(limit))

            var rows: [Sample.Index.FileSearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let projectId = String(cString: sqlite3_column_text(statement, 0))
                let path = String(cString: sqlite3_column_text(statement, 1))
                let filename = String(cString: sqlite3_column_text(statement, 2))
                let snippet = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let rank = sqlite3_column_double(statement, 4)
                rows.append(Sample.Index.FileSearchResult(
                    projectId: projectId,
                    path: path,
                    filename: filename,
                    snippet: snippet,
                    rank: rank
                ))
            }
            return rows
        }

        /// Get total import count (#81)
        public func importCount() async throws -> Int {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = Shared.Utils.SQL.countRows(in: "file_imports")

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// Clear all data
        public func clearAll() async throws {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            let sql = """
            DELETE FROM files_fts;
            DELETE FROM files;
            DELETE FROM projects_fts;
            DELETE FROM projects;
            """

            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }

            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
                throw Sample.Index.Error.sqliteError("Failed to clear: \(errorMessage)")
            }
        }

        /// Delete a project and its files
        public func deleteProject(id: String) async throws {
            guard let database else {
                throw Sample.Index.Error.databaseNotInitialized
            }

            // Delete files first (FTS, then main table)
            let deleteFilesFTS = "DELETE FROM files_fts WHERE project_id = ?;"
            var stmt1: OpaquePointer?
            if sqlite3_prepare_v2(database, deleteFilesFTS, -1, &stmt1, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt1, 1, (id as NSString).utf8String, -1, nil)
                _ = sqlite3_step(stmt1)
                sqlite3_finalize(stmt1)
            }

            let deleteFiles = "DELETE FROM files WHERE project_id = ?;"
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(database, deleteFiles, -1, &stmt2, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt2, 1, (id as NSString).utf8String, -1, nil)
                _ = sqlite3_step(stmt2)
                sqlite3_finalize(stmt2)
            }

            // Delete project (FTS, then main table)
            let deleteProjectFTS = "DELETE FROM projects_fts WHERE id = ?;"
            var stmt3: OpaquePointer?
            if sqlite3_prepare_v2(database, deleteProjectFTS, -1, &stmt3, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt3, 1, (id as NSString).utf8String, -1, nil)
                _ = sqlite3_step(stmt3)
                sqlite3_finalize(stmt3)
            }

            let deleteProject = "DELETE FROM projects WHERE id = ?;"
            var stmt4: OpaquePointer?
            if sqlite3_prepare_v2(database, deleteProject, -1, &stmt4, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt4, 1, (id as NSString).utf8String, -1, nil)
                _ = sqlite3_step(stmt4)
                sqlite3_finalize(stmt4)
            }
        }
    }
}
