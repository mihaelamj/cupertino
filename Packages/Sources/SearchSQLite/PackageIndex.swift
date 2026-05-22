import ASTIndexer
import CorePackageIndexingModels
import CoreProtocols
import Foundation
import LoggingModels
import SearchModels
import SharedConstants
import SQLite3

// MARK: - Package Index (separate DB)

extension Search {
    /// Dedicated SQLite/FTS5 index for Swift package content (README, CHANGELOG,
    /// DocC articles, source, tests, examples). Lives at `~/.cupertino/packages.db`
    /// so the main `search.db` stays focused on Apple docs and related first-party
    /// sources; cross-indexing can be added later in the search layer if desired.
    ///
    /// Design notes:
    /// - `package_files_fts.content` keeps the raw file content (prose + code).
    /// - `package_files_fts.symbols` holds the raw content PLUS a case-split form
    ///   (`makeHTTPRequest` becomes `make HTTP Request`), which is what lets Swift
    ///   identifiers actually be searchable by token. Without this column, a
    ///   query for "request" never finds `makeHTTPRequest` because FTS5's default
    ///   tokenizer won't split camelCase.
    /// - `kind` is stored `UNINDEXED` so it survives in SELECTs but doesn't bloat
    ///   the FTS index. Callers filter on it via the plain-column path.
    public actor PackageIndex {
        /// Bumped 4 → 5 in the #860 fix: new `package_imports` table
        /// (mirrors samples.db's `file_imports`). Captures the
        /// `import X` statements the AST extractor surfaces per .swift
        /// file. `Search.PackageIndex.applyAppleImports` now joins
        /// against `package_imports.module_name` instead of
        /// `package_files.module` (the package's OWN module name was
        /// the wrong RHS for "frameworks this package imports").
        ///
        /// Earlier history: 1 → 2 in the #219 follow-up (six
        /// availability columns on `package_metadata` + one on
        /// `package_files`); 2 → 3 in #225 Part A
        /// (`swift_tools_version` column); 3 → 4 in #837
        /// (`apple_imports_json` + `enrichment_version` columns +
        /// `package_symbols` table); 4 → 5 in #860 (this).
        ///
        /// Existing v1-v4 DBs migrate idempotently via `ALTER TABLE
        /// ADD COLUMN` (pre-v4 columns) and `CREATE TABLE IF NOT
        /// EXISTS` (`package_symbols` + `package_imports`). No
        /// destructive migration.
        public static let schemaVersion: Int32 = 5

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
            let directory = dbPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try openDatabase()
            try migrateSchema()
            try createTables()
            try setSchemaVersion()
            isInitialized = true
        }

        public func disconnect() {
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
        }

        /// Inspect `PRAGMA synchronous` on the actor's own connection
        /// (returns 0..3, matching SQLite's enum: 0=OFF, 1=NORMAL,
        /// 2=FULL, 3=EXTRA). Per-connection setting; not persistent
        /// in the file header, so `Diagnostics.Probes` opening its
        /// own connection would see SQLite's defaults. Test-facing.
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
        /// connection (bytes, -1 = unlimited). Same per-connection
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

        /// Inspect `PRAGMA foreign_keys` on the actor's own connection
        /// (0 = OFF, 1 = ON). Per-connection setting, not persisted in
        /// the file header — `Diagnostics.Probes` opening its own
        /// connection would see SQLite's default (0). Test-facing
        /// (#864): if a future edit removes the `PRAGMA foreign_keys
        /// = ON` line from `openDatabase`, the regression test in
        /// `Issue864PackagesReRunOrphansTests` fails by reading this.
        public func currentForeignKeysMode() -> Int32? {
            guard let database else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, "PRAGMA foreign_keys;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int(stmt, 0)
        }

        // MARK: - Public API

        public struct IndexResult: Sendable {
            public let filesIndexed: Int
            public let bytesIndexed: Int64
        }

        /// Per-package availability payload from `availability.json` (#219).
        /// Optional — when nil, the deployment-target columns and the
        /// per-file `available_attrs_json` column stay NULL so callers can
        /// still distinguish "not annotated" from "annotated with no
        /// availability info".
        public struct AvailabilityPayload: Sendable {
            public let deploymentTargets: [String: String]
            /// File-keyed list of @available attribute occurrences.
            public let attributesByRelpath: [String: [FileAttribute]]
            /// Free-form tag describing where this came from. Currently only
            /// `"package-swift"` (parsed from Package.swift + .swift sources
            /// by `PackageAvailabilityAnnotator`).
            public let source: String
            /// Authored Swift compiler floor from Package.swift line 1
            /// (#225 Part A). Nil when the manifest didn't carry a
            /// `swift-tools-version: X.Y` declaration. Default-nil so
            /// existing call sites compile unchanged.
            public let swiftToolsVersion: String?

            public struct FileAttribute: Sendable {
                public let line: Int
                public let raw: String
                public let platforms: [String]
                public init(line: Int, raw: String, platforms: [String]) {
                    self.line = line
                    self.raw = raw
                    self.platforms = platforms
                }
            }

            public init(
                deploymentTargets: [String: String],
                attributesByRelpath: [String: [FileAttribute]],
                source: String,
                swiftToolsVersion: String? = nil
            ) {
                self.deploymentTargets = deploymentTargets
                self.attributesByRelpath = attributesByRelpath
                self.source = source
                self.swiftToolsVersion = swiftToolsVersion
            }
        }

        /// Index a single package end-to-end. Wipes any prior rows for the same
        /// (owner, repo) first so re-indexes converge cleanly without FTS5
        /// duplicate-row issues. All SQL runs in one transaction per package.
        public func index(
            resolved: Core.PackageIndexing.ResolvedPackage,
            extraction: Core.PackageIndexing.PackageExtractionResult,
            stars: Int? = nil,
            hostedDocumentationURL: URL? = nil,
            availability: AvailabilityPayload? = nil
        ) throws -> IndexResult {
            guard let database else {
                throw PackageIndexError.databaseNotInitialized
            }
            try execute("BEGIN TRANSACTION")

            do {
                try deleteExistingRows(owner: resolved.owner, repo: resolved.repo)
                let packageId = try insertMetadata(
                    resolved: resolved,
                    extraction: extraction,
                    stars: stars,
                    hostedDocumentationURL: hostedDocumentationURL,
                    availability: availability
                )
                var bytes: Int64 = 0
                for file in extraction.files {
                    try insertFile(
                        packageId: packageId,
                        resolved: resolved,
                        file: file,
                        availability: availability
                    )
                    bytes += Int64(file.byteSize)
                }
                try execute("COMMIT")
                _ = database
                return IndexResult(filesIndexed: extraction.files.count, bytesIndexed: bytes)
            } catch {
                // #673 Phase B — surface a ROLLBACK failure so the next
                // BEGIN doesn't fail mysteriously with "cannot start a
                // transaction within a transaction". Pre-fix this was
                // silent, leaving the writer actor in a stuck-
                // transaction state with no observability.
                do {
                    try execute("ROLLBACK")
                } catch let rollbackError {
                    logger.warning(
                        "ROLLBACK failed after package-indexing error " +
                            "(transaction state may be stuck): \(rollbackError)",
                        category: .search
                    )
                }
                throw error
            }
        }

        public struct Summary: Sendable {
            public let packageCount: Int
            public let fileCount: Int
            public let bytesIndexed: Int64
        }

        public func summary() throws -> Summary {
            guard let database else {
                throw PackageIndexError.databaseNotInitialized
            }
            let packages = try Int(selectScalar(Shared.Utils.SQL.countRows(in: "package_metadata")))
            let files = try Int(selectScalar(Shared.Utils.SQL.countRows(in: "package_files")))
            let bytes = try selectScalar("SELECT IFNULL(SUM(size_bytes), 0) FROM package_files")
            _ = database
            return Summary(packageCount: packages, fileCount: files, bytesIndexed: bytes)
        }

        // MARK: - Schema

        private func createTables() throws {
            let sql = """
            CREATE TABLE IF NOT EXISTS package_metadata (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner TEXT NOT NULL,
                repo TEXT NOT NULL,
                url TEXT NOT NULL,
                branch_used TEXT,
                stars INTEGER,
                is_apple_official INTEGER NOT NULL DEFAULT 0,
                tarball_bytes INTEGER,
                total_bytes INTEGER,
                fetched_at INTEGER NOT NULL,
                cupertino_version TEXT,
                hosted_doc_url TEXT,
                parents_json TEXT,
                -- Availability columns (#219, mirrors docs_metadata pattern)
                min_ios TEXT,
                min_macos TEXT,
                min_tvos TEXT,
                min_watchos TEXT,
                min_visionos TEXT,
                availability_source TEXT,
                -- #225 Part A — Swift compiler floor from Package.swift's
                -- `// swift-tools-version: X.Y` declaration. Authored,
                -- not derived from min_ios (issue body explicitly
                -- rejects that inference). Nil for older corpora or
                -- packages whose manifest doesn't declare the version
                -- in a parseable shape.
                swift_tools_version TEXT,
                -- #837 stage 1: aggregate of Apple framework modules
                -- the package imports. JSON array of module names like
                -- ["SwiftUI","Combine"]; NULL until the
                -- packages-apple-imports pass populates it.
                apple_imports_json TEXT,
                -- #837 stage 1: tracks which enrichment pass version
                -- last wrote this row. NULL until any pass runs.
                enrichment_version INTEGER,
                UNIQUE(owner, repo)
            );

            CREATE INDEX IF NOT EXISTS idx_pkg_owner ON package_metadata(owner);
            CREATE INDEX IF NOT EXISTS idx_pkg_apple ON package_metadata(is_apple_official);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_ios ON package_metadata(min_ios);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_macos ON package_metadata(min_macos);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_tvos ON package_metadata(min_tvos);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_watchos ON package_metadata(min_watchos);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_visionos ON package_metadata(min_visionos);
            CREATE INDEX IF NOT EXISTS idx_pkg_swift_tools ON package_metadata(swift_tools_version);
            CREATE INDEX IF NOT EXISTS idx_pkg_enrichment ON package_metadata(enrichment_version);

            CREATE TABLE IF NOT EXISTS package_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                package_id INTEGER NOT NULL,
                relpath TEXT NOT NULL,
                kind TEXT NOT NULL,
                module TEXT,
                size_bytes INTEGER NOT NULL,
                indexed_at INTEGER NOT NULL,
                -- Per-file @available occurrences (#219). JSON array of
                -- {line, raw, platforms[]}. NULL = file wasn't annotated.
                available_attrs_json TEXT,
                FOREIGN KEY(package_id) REFERENCES package_metadata(id) ON DELETE CASCADE,
                UNIQUE(package_id, relpath)
            );

            CREATE INDEX IF NOT EXISTS idx_file_package ON package_files(package_id);
            CREATE INDEX IF NOT EXISTS idx_file_kind ON package_files(kind);
            CREATE INDEX IF NOT EXISTS idx_file_module ON package_files(module);

            CREATE VIRTUAL TABLE IF NOT EXISTS package_files_fts USING fts5(
                package_id UNINDEXED,
                owner UNINDEXED,
                repo UNINDEXED,
                module UNINDEXED,
                relpath UNINDEXED,
                kind UNINDEXED,
                title,
                content,
                symbols,
                tokenize='porter unicode61'
            );

            -- #837 stage 2: per-symbol storage on packages.db, parallel
            -- to samples.db's file_symbols. Populated by the AST
            -- extraction pass during cupertino save --packages so the
            -- postprocessor's apple-constraints pass can annotate
            -- generic_constraints on packages the same way it does on
            -- search.db's doc_symbols and samples.db's file_symbols.
            CREATE TABLE IF NOT EXISTS package_symbols (
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
                generic_constraints TEXT,
                enrichment_version INTEGER,
                FOREIGN KEY (file_id) REFERENCES package_files(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_package_symbols_file ON package_symbols(file_id);
            CREATE INDEX IF NOT EXISTS idx_package_symbols_kind ON package_symbols(kind);
            CREATE INDEX IF NOT EXISTS idx_package_symbols_name ON package_symbols(name);
            CREATE INDEX IF NOT EXISTS idx_package_symbols_enrichment ON package_symbols(enrichment_version);

            -- #837 stage 1: per-package aggregate of Apple frameworks
            -- the package imports. JSON array of module names (e.g.
            -- ["SwiftUI","Combine"]), populated by the postprocessor's
            -- packages-apple-imports pass joining `package_imports`
            -- (see below) against the AppleSymbolGraphsKit module list.
            -- NULL = the pass hasn't run on this package yet.
            -- enrichment_version tracks the pass version that last
            -- wrote the row.
            -- (Added via ALTER below for v3→v4 migration, defined
            -- inline here for fresh DBs.)

            -- #860 fix: per-file capture of `import X` statements the
            -- AST extractor surfaces. Mirrors samples.db's
            -- `file_imports`. Pre-#860, the apple-imports pass joined
            -- against `package_files.module` (the package's OWN Swift
            -- module name, e.g. Soto / Vapor / Rules) which made
            -- coverage 1/183 because that's the wrong RHS for
            -- "frameworks this package imports". Post-#860, the pass
            -- joins against `package_imports.module_name` and gets
            -- the actual `import SwiftUI` / `import Combine` set.
            CREATE TABLE IF NOT EXISTS package_imports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_id INTEGER NOT NULL,
                module_name TEXT NOT NULL,
                line INTEGER NOT NULL,
                is_exported INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (file_id) REFERENCES package_files(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_package_imports_file ON package_imports(file_id);
            CREATE INDEX IF NOT EXISTS idx_package_imports_module ON package_imports(module_name);
            """
            try execute(sql)
        }

        private func setSchemaVersion() throws {
            try execute("PRAGMA user_version = \(Self.schemaVersion)")
        }

        /// Read the on-disk schema version and run any incremental
        /// `ALTER TABLE` migrations needed to reach `schemaVersion`.
        /// Mirrors `Search.Index.checkAndMigrateSchema` (SearchIndex.swift)
        /// — fresh databases (user_version = 0) skip the migrations because
        /// `createTables()` runs immediately after with the latest schema.
        private func migrateSchema() throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW
            else { return }
            let currentVersion = sqlite3_column_int(statement, 0)
            sqlite3_finalize(statement)
            statement = nil

            guard currentVersion > 0 else { return } // fresh DB
            guard currentVersion < Self.schemaVersion else { return } // already current

            if currentVersion < 2 {
                try migrateToVersion2()
            }
            if currentVersion < 3 {
                try migrateToVersion3()
            }
            if currentVersion < 4 {
                try migrateToVersion4()
            }
            if currentVersion < 5 {
                try migrateToVersion5()
            }
        }

        /// Version 4 → 5 (#860): adds the `package_imports` table
        /// parallel to samples.db's `file_imports`. Captures the
        /// `import X` statements the AST extractor surfaces per .swift
        /// file. Idempotent CREATE TABLE IF NOT EXISTS pattern; no
        /// destructive migration. The `AppleImportsPass` join column
        /// flips from `package_files.module` (which carried the
        /// package's OWN module name, the wrong RHS for "frameworks
        /// this package imports") to `package_imports.module_name`
        /// (the actual import statements).
        private func migrateToVersion5() throws {
            try execute("""
            CREATE TABLE IF NOT EXISTS package_imports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_id INTEGER NOT NULL,
                module_name TEXT NOT NULL,
                line INTEGER NOT NULL,
                is_exported INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (file_id) REFERENCES package_files(id) ON DELETE CASCADE
            );
            """)
            try execute("CREATE INDEX IF NOT EXISTS idx_package_imports_file ON package_imports(file_id);")
            try execute("CREATE INDEX IF NOT EXISTS idx_package_imports_module ON package_imports(module_name);")
        }

        /// Version 3 → 4 (#837 stage 1 + 2): adds the `package_symbols`
        /// table parallel to samples.db's `file_symbols`, plus
        /// `apple_imports_json` and `enrichment_version` columns on
        /// `package_metadata`. Indexes match the samples + docs pattern.
        /// ALTER statements ignore "duplicate column" errors so the
        /// migration is harmless to re-run.
        private func migrateToVersion4() throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            var errPtr: UnsafeMutablePointer<CChar>?

            // package_metadata column additions
            _ = sqlite3_exec(database, "ALTER TABLE package_metadata ADD COLUMN apple_imports_json TEXT;", nil, nil, &errPtr)
            sqlite3_free(errPtr)
            errPtr = nil
            _ = sqlite3_exec(database, "ALTER TABLE package_metadata ADD COLUMN enrichment_version INTEGER;", nil, nil, &errPtr)
            sqlite3_free(errPtr)

            // package_symbols table (CREATE TABLE IF NOT EXISTS is
            // already idempotent so no swallowed-error dance needed).
            try execute("""
            CREATE TABLE IF NOT EXISTS package_symbols (
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
                generic_constraints TEXT,
                enrichment_version INTEGER,
                FOREIGN KEY (file_id) REFERENCES package_files(id) ON DELETE CASCADE
            );
            """)
            try execute("CREATE INDEX IF NOT EXISTS idx_package_symbols_file ON package_symbols(file_id);")
            try execute("CREATE INDEX IF NOT EXISTS idx_package_symbols_kind ON package_symbols(kind);")
            try execute("CREATE INDEX IF NOT EXISTS idx_package_symbols_name ON package_symbols(name);")
            try execute("CREATE INDEX IF NOT EXISTS idx_package_symbols_enrichment ON package_symbols(enrichment_version);")
            try execute("CREATE INDEX IF NOT EXISTS idx_pkg_enrichment ON package_metadata(enrichment_version);")
        }

        /// Version 2 → 3 (#225 Part A): add `swift_tools_version` column
        /// to `package_metadata` for the Swift compiler floor parsed
        /// from `Package.swift` line 1. ALTER ignores "duplicate column"
        /// errors so re-running the migration is harmless.
        private func migrateToVersion3() throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            var errPtr: UnsafeMutablePointer<CChar>?
            _ = sqlite3_exec(database, "ALTER TABLE package_metadata ADD COLUMN swift_tools_version TEXT;", nil, nil, &errPtr)
            sqlite3_free(errPtr)
            try execute("CREATE INDEX IF NOT EXISTS idx_pkg_swift_tools ON package_metadata(swift_tools_version);")
        }

        /// Version 1 → 2 (#219 follow-up): add availability columns to
        /// `package_metadata` and a `available_attrs_json` column to
        /// `package_files`. Indexes match the docs_metadata pattern in
        /// SearchIndex. ALTER statements ignore "duplicate column" errors
        /// so re-running the migration is harmless.
        private func migrateToVersion2() throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }

            let alters = [
                "ALTER TABLE package_metadata ADD COLUMN min_ios TEXT;",
                "ALTER TABLE package_metadata ADD COLUMN min_macos TEXT;",
                "ALTER TABLE package_metadata ADD COLUMN min_tvos TEXT;",
                "ALTER TABLE package_metadata ADD COLUMN min_watchos TEXT;",
                "ALTER TABLE package_metadata ADD COLUMN min_visionos TEXT;",
                "ALTER TABLE package_metadata ADD COLUMN availability_source TEXT;",
                "ALTER TABLE package_files ADD COLUMN available_attrs_json TEXT;",
            ]
            for sql in alters {
                var errPtr: UnsafeMutablePointer<CChar>?
                _ = sqlite3_exec(database, sql, nil, nil, &errPtr)
                sqlite3_free(errPtr)
            }

            let indexes = [
                "CREATE INDEX IF NOT EXISTS idx_pkg_min_ios ON package_metadata(min_ios);",
                "CREATE INDEX IF NOT EXISTS idx_pkg_min_macos ON package_metadata(min_macos);",
                "CREATE INDEX IF NOT EXISTS idx_pkg_min_tvos ON package_metadata(min_tvos);",
                "CREATE INDEX IF NOT EXISTS idx_pkg_min_watchos ON package_metadata(min_watchos);",
                "CREATE INDEX IF NOT EXISTS idx_pkg_min_visionos ON package_metadata(min_visionos);",
            ]
            for sql in indexes {
                try execute(sql)
            }
        }

        // MARK: - Inserts

        private func deleteExistingRows(owner: String, repo: String) throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            // Find existing id first; FTS5 can't be DELETEd by owner/repo directly
            // because those columns are UNINDEXED.
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "SELECT id FROM package_metadata WHERE owner = ? AND repo = ?"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
            sqlite3_bind_text(statement, 1, owner, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, repo, -1, SQLITE_TRANSIENT)
            var existingId: Int64?
            if sqlite3_step(statement) == SQLITE_ROW {
                existingId = sqlite3_column_int64(statement, 0)
            }
            guard let id = existingId else { return }

            try executeBinding(
                "DELETE FROM package_files_fts WHERE package_id = ?",
                binders: [{ stmt in sqlite3_bind_int64(stmt, 1, id) }]
            )
            try executeBinding(
                "DELETE FROM package_files WHERE package_id = ?",
                binders: [{ stmt in sqlite3_bind_int64(stmt, 1, id) }]
            )
            try executeBinding(
                "DELETE FROM package_metadata WHERE id = ?",
                binders: [{ stmt in sqlite3_bind_int64(stmt, 1, id) }]
            )
        }

        private func insertMetadata(
            resolved: Core.PackageIndexing.ResolvedPackage,
            extraction: Core.PackageIndexing.PackageExtractionResult,
            stars: Int?,
            hostedDocumentationURL: URL?,
            availability: AvailabilityPayload?
        ) throws -> Int64 {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            let sql = """
            INSERT INTO package_metadata (
                owner, repo, url, branch_used, stars, is_apple_official,
                tarball_bytes, total_bytes, fetched_at, cupertino_version,
                hosted_doc_url, parents_json,
                min_ios, min_macos, min_tvos, min_watchos, min_visionos, availability_source,
                swift_tools_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
            // #682 — surface JSONEncoder failure instead of silently
            // losing the parents chain. `resolved.parents` is a Codable
            // [ResolvedPackage] — encode failure should be impossible in
            // practice (no funky types in the value), but if it ever
            // does happen we want a log line rather than a "[]" with no
            // explanation.
            let parentsJSON: String
            do {
                let data = try JSONEncoder().encode(resolved.parents)
                parentsJSON = String(data: data, encoding: .utf8) ?? "[]"
            } catch {
                logger.error(
                    "PackageIndex: failed to encode parents for \(resolved.owner)/\(resolved.repo): \(error). Storing empty array as fallback.",
                    category: .search
                )
                parentsJSON = "[]"
            }
            let isApple: Int32 = resolved.priority == .appleOfficial ? 1 : 0

            sqlite3_bind_text(statement, 1, resolved.owner, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, resolved.repo, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, resolved.url, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, extraction.branch, -1, SQLITE_TRANSIENT)
            if let stars { sqlite3_bind_int64(statement, 5, Int64(stars)) } else { sqlite3_bind_null(statement, 5) }
            sqlite3_bind_int(statement, 6, isApple)
            sqlite3_bind_int64(statement, 7, Int64(extraction.tarballBytes))
            sqlite3_bind_int64(statement, 8, extraction.totalBytes)
            sqlite3_bind_int64(statement, 9, Int64(Date().timeIntervalSince1970))
            sqlite3_bind_text(statement, 10, Shared.Constants.App.version, -1, SQLITE_TRANSIENT)
            if let hostedDocumentationURL {
                sqlite3_bind_text(statement, 11, hostedDocumentationURL.absoluteString, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 11)
            }
            sqlite3_bind_text(statement, 12, parentsJSON, -1, SQLITE_TRANSIENT)

            /// Availability columns 13-18 (#219)
            func bindMin(_ pos: Int32, _ key: String) {
                if let value = availability?.deploymentTargets[key] {
                    sqlite3_bind_text(statement, pos, value, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, pos)
                }
            }
            bindMin(13, "iOS")
            bindMin(14, "macOS")
            bindMin(15, "tvOS")
            bindMin(16, "watchOS")
            bindMin(17, "visionOS")
            if let source = availability?.source {
                sqlite3_bind_text(statement, 18, source, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 18)
            }

            // #225 Part A — column 19. Nil for older corpora / manifests
            // whose declaration we couldn't parse.
            if let swiftTools = availability?.swiftToolsVersion {
                sqlite3_bind_text(statement, 19, swiftTools, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 19)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
            return sqlite3_last_insert_rowid(database)
        }

        private func insertFile(
            packageId: Int64,
            resolved: Core.PackageIndexing.ResolvedPackage,
            file: Core.PackageIndexing.ExtractedFile,
            availability: AvailabilityPayload?
        ) throws {
            guard database != nil else { throw PackageIndexError.databaseNotInitialized }

            // Pre-compute the per-file availability JSON (NULL when no
            // attrs were recorded for this relpath).
            let attrsJSON: String?
            if let attrs = availability?.attributesByRelpath[file.relpath], !attrs.isEmpty {
                struct Encoded: Encodable {
                    let line: Int
                    let raw: String
                    let platforms: [String]
                }
                let encoded = attrs.map { Encoded(line: $0.line, raw: $0.raw, platforms: $0.platforms) }
                // #682 — surface JSONEncoder failure instead of silently
                // losing per-file availability metadata. Same shape as the
                // parents-encode fix at line 412 above.
                do {
                    let data = try JSONEncoder().encode(encoded)
                    attrsJSON = String(data: data, encoding: .utf8)
                } catch {
                    logger.error(
                        "PackageIndex: failed to encode availability attrs for \(file.relpath): \(error). Storing NULL as fallback.",
                        category: .search
                    )
                    attrsJSON = nil
                }
            } else {
                attrsJSON = nil
            }

            let insertPackageFileSQL = """
            INSERT INTO package_files (
                package_id, relpath, kind, module, size_bytes, indexed_at,
                available_attrs_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            try executeBinding(insertPackageFileSQL, binders: [
                { stmt in sqlite3_bind_int64(stmt, 1, packageId) },
                { stmt in sqlite3_bind_text(stmt, 2, file.relpath, -1, SQLITE_TRANSIENT) },
                { stmt in sqlite3_bind_text(stmt, 3, file.kind.rawValue, -1, SQLITE_TRANSIENT) },
                { stmt in
                    if let module = file.module {
                        sqlite3_bind_text(stmt, 4, module, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(stmt, 4)
                    }
                },
                { stmt in sqlite3_bind_int64(stmt, 5, Int64(file.byteSize)) },
                { stmt in sqlite3_bind_int64(stmt, 6, Int64(Date().timeIntervalSince1970)) },
                { stmt in
                    if let attrsJSON {
                        sqlite3_bind_text(stmt, 7, attrsJSON, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(stmt, 7)
                    }
                },
            ])

            let title = Self.extractTitle(relpath: file.relpath, content: file.content)
            let symbols = Self.symbolTokens(from: file.content)

            let insertFTSSQL = """
            INSERT INTO package_files_fts (
                package_id, owner, repo, module, relpath, kind, title, content, symbols
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            try executeBinding(insertFTSSQL, binders: [
                { stmt in sqlite3_bind_int64(stmt, 1, packageId) },
                { stmt in sqlite3_bind_text(stmt, 2, resolved.owner, -1, SQLITE_TRANSIENT) },
                { stmt in sqlite3_bind_text(stmt, 3, resolved.repo, -1, SQLITE_TRANSIENT) },
                { stmt in
                    if let module = file.module {
                        sqlite3_bind_text(stmt, 4, module, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(stmt, 4)
                    }
                },
                { stmt in sqlite3_bind_text(stmt, 5, file.relpath, -1, SQLITE_TRANSIENT) },
                { stmt in sqlite3_bind_text(stmt, 6, file.kind.rawValue, -1, SQLITE_TRANSIENT) },
                { stmt in sqlite3_bind_text(stmt, 7, title, -1, SQLITE_TRANSIENT) },
                { stmt in sqlite3_bind_text(stmt, 8, file.content, -1, SQLITE_TRANSIENT) },
                { stmt in sqlite3_bind_text(stmt, 9, symbols, -1, SQLITE_TRANSIENT) },
            ])

            // #837 stage 2: AST extraction for .swift files into the
            // new package_symbols table. Mirrors what samples.db's
            // Sample.Index.Database.indexSymbols does for samples. The
            // package_files INSERT above used AUTOINCREMENT so we read
            // the row's id via sqlite3_last_insert_rowid for the
            // foreign key.
            //
            // #860 fix: the same AST extraction result carries the
            // `import X` statements as `result.imports`. Pipe those
            // into the new `package_imports` table so the
            // apple-imports enrichment pass has a real RHS to join
            // against. Pre-#860, the pass joined against
            // `package_files.module` (the package's OWN Swift module
            // name) and got 1/183 coverage because that wasn't the
            // shape of "frameworks this package imports".
            if file.relpath.hasSuffix(".swift") {
                guard let database else { return }
                let fileId = sqlite3_last_insert_rowid(database)
                let extractor = ASTIndexer.Extractor()
                let result = extractor.extract(from: file.content)
                try indexPackageSymbols(fileId: fileId, symbols: result.symbols)
                try indexPackageImports(fileId: fileId, imports: result.imports)
            }
        }

        /// #837 stage 2 — apply the authoritative Apple-type generic
        /// constraints table over `package_symbols.generic_constraints`.
        /// Parallels `Search.Index.applyAppleStaticConstraints` for
        /// search.db and `Sample.Index.Database.applyAppleStaticConstraints`
        /// for samples.db. Matches on the lowercased symbol name (last
        /// segment of `entry.docURI`); writes the joined-comma constraint
        /// blob; stamps `enrichment_version`.
        ///
        /// Returns affected-row count. If `lookup` is nil, returns 0.
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
            UPDATE package_symbols
            SET generic_constraints = ?, enrichment_version = ?
            WHERE LOWER(name) = ?;
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                _ = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                throw PackageIndexError.sqliteError("prepare applyAppleStaticConstraints UPDATE failed")
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

        /// #837 stage 1 — populate `package_metadata.apple_imports_json`
        /// per package: JSON array of Apple framework modules the
        /// package imports, derived by joining `package_files.module`
        /// against the Apple module set extracted from the constraints
        /// lookup (entries' `docURI` second segment is the framework
        /// slug; the union of those is our Apple-module set).
        ///
        /// Stamps `enrichment_version` on each updated package row.
        public func applyAppleImports(
            lookup: (any Search.StaticConstraintsLookup)?,
            enrichmentVersion: Int = 1
        ) async throws -> Int {
            guard let lookup, let database else { return 0 }
            let entries = try await lookup.allEntries()
            guard !entries.isEmpty else { return 0 }

            // Derive the set of Apple framework module slugs from
            // entry docURIs (apple-docs://<framework>/...).
            var appleModules: Set<String> = []
            for entry in entries {
                guard let stripped = entry.docURI.split(separator: ":").last else { continue }
                let segments = stripped.split(separator: "/").filter { !$0.isEmpty }
                guard let first = segments.first else { continue }
                appleModules.insert(String(first).lowercased())
            }
            guard !appleModules.isEmpty else { return 0 }

            // #860 fix: build per-package module list from
            // `package_imports` (the canonical `import X` statements
            // the AST extractor surfaced per .swift file), JOINed up
            // to `package_files` for `package_id`. Pre-#860 this
            // query read `LOWER(package_files.module)` — which is the
            // package's OWN module name (Soto / Vapor / Rules), not
            // the Apple frameworks the package imports — so coverage
            // was 1/183 (only matched by accident on `apple/swift-
            // system` whose module is literally `System`). Post-#860
            // the join column is `package_imports.module_name` and
            // coverage tracks the real `import SwiftUI` /
            // `import Combine` pattern.
            //
            // #860 follow-up — submodule-path normalisation. Swift
            // allows `import Foundation.URL` /
            // `import Foundation.ProcessInfo` to import a specific
            // submodule. The AST extractor preserves the dotted
            // suffix in `module_name`, but the constraint lookup's
            // Apple framework slug is the bare framework prefix
            // (`foundation`). Without normalisation, packages like
            // `mxcl/Version` (which only carries `Foundation.*`
            // submodule imports) showed up empty even though every
            // `Foundation.X` import is semantically importing
            // Foundation. The SQL splits at the first dot via
            // `INSTR(module_name || '.', '.')` so a row like
            // `Foundation.URL` reduces to `foundation` for join
            // purposes; bare imports like `SwiftUI` stay `swiftui`
            // unchanged.
            let selectSQL = """
            SELECT
                pf.package_id,
                LOWER(SUBSTR(pi.module_name, 1, INSTR(pi.module_name || '.', '.') - 1))
            FROM package_imports pi
            JOIN package_files pf ON pi.file_id = pf.id;
            """
            var perPackage: [Int64: Set<String>] = [:]
            var selectStmt: OpaquePointer?
            defer { sqlite3_finalize(selectStmt) }
            guard sqlite3_prepare_v2(database, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
                throw PackageIndexError.sqliteError("prepare select package_imports for apple-imports failed")
            }
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                let pkgId = sqlite3_column_int64(selectStmt, 0)
                guard let modulePtr = sqlite3_column_text(selectStmt, 1) else { continue }
                let module = String(cString: modulePtr)
                if appleModules.contains(module) {
                    perPackage[pkgId, default: []].insert(module)
                }
            }
            sqlite3_finalize(selectStmt)
            selectStmt = nil

            // UPDATE one row per package with the (sorted) JSON array.
            _ = sqlite3_exec(database, "BEGIN TRANSACTION", nil, nil, nil)
            let updateSQL = """
            UPDATE package_metadata
            SET apple_imports_json = ?, enrichment_version = ?
            WHERE id = ?;
            """
            var updateStmt: OpaquePointer?
            defer { sqlite3_finalize(updateStmt) }
            guard sqlite3_prepare_v2(database, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
                _ = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                throw PackageIndexError.sqliteError("prepare apple_imports UPDATE failed")
            }
            var affected = 0
            for (pkgId, modules) in perPackage {
                let sorted = modules.sorted()
                guard let jsonData = try? JSONEncoder().encode(sorted),
                      let jsonString = String(data: jsonData, encoding: .utf8)
                else { continue }
                sqlite3_reset(updateStmt)
                sqlite3_clear_bindings(updateStmt)
                sqlite3_bind_text(updateStmt, 1, (jsonString as NSString).utf8String, -1, nil)
                sqlite3_bind_int(updateStmt, 2, Int32(enrichmentVersion))
                sqlite3_bind_int64(updateStmt, 3, pkgId)
                _ = sqlite3_step(updateStmt)
                affected += Int(sqlite3_changes(database))
            }
            _ = sqlite3_exec(database, "COMMIT", nil, nil, nil)
            return affected
        }

        /// Insert AST-extracted symbols into the `package_symbols` table.
        /// Parallels `Sample.Index.Database.indexSymbols` from samples.db.
        /// Caller guarantees the surrounding transaction. Symbols that
        /// fail to bind are silently skipped (same policy as the samples
        /// indexer; an entire package is not torn down for one bad
        /// symbol).
        private func indexPackageSymbols(fileId: Int64, symbols: [ASTIndexer.Symbol]) throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            guard !symbols.isEmpty else { return }

            let sql = """
            INSERT INTO package_symbols
            (file_id, name, kind, line, column, signature, is_async, is_throws,
             is_public, is_static, attributes, conformances, generic_params)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            for symbol in symbols {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    continue
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
                let genericParamsStr = symbol.genericParameters.isEmpty
                    ? nil
                    : symbol.genericParameters.joined(separator: ",")
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
            }
        }

        /// #860 — insert AST-extracted `import X` statements into
        /// `package_imports`. Parallels
        /// `Sample.Index.Database.indexImports` from samples.db. The
        /// `Search.PackageIndexer.indexPackage` AST-extraction block
        /// calls this once per .swift file after `indexPackageSymbols`,
        /// inside the same per-package transaction.
        ///
        /// The pre-#860 indexer never captured imports at all, which
        /// is why `applyAppleImports` had no join column with the
        /// right shape. Now `package_imports.module_name` carries the
        /// canonical `SwiftUI` / `Combine` / `Foundation` set per
        /// file; the pass groups by package_id and writes the JSON
        /// aggregate into `package_metadata.apple_imports_json`.
        ///
        /// Empty `imports` is a fast-path no-op. Bind failures are
        /// silently skipped (one bad import shouldn't tear down the
        /// whole package).
        private func indexPackageImports(fileId: Int64, imports: [ASTIndexer.Import]) throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            guard !imports.isEmpty else { return }

            let sql = """
            INSERT INTO package_imports (file_id, module_name, line, is_exported)
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

        // MARK: - Helpers

        private func execute(_ sql: String) throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }
            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let message = errorPointer.map { String(cString: $0) } ?? "unknown"
                throw PackageIndexError.sqliteError(message)
            }
        }

        private func executeBinding(
            _ sql: String,
            binders: [(OpaquePointer?) -> Int32]
        ) throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
            for binder in binders {
                _ = binder(statement)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
        }

        private func selectScalar(_ sql: String) throws -> Int64 {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }
            return sqlite3_column_int64(statement, 0)
        }

        private func openDatabase() throws {
            var dbPointer: OpaquePointer?
            guard sqlite3_open(dbPath.path, &dbPointer) == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(dbPointer))
                sqlite3_close(dbPointer)
                throw PackageIndexError.sqliteError("Failed to open \(dbPath.lastPathComponent): \(message)")
            }

            // #236: WAL journal mode lets readers (`cupertino search
            // --source packages`, `cupertino doctor`) proceed while a
            // `cupertino save --packages` writer holds the DB. PRAGMA is
            // idempotent and persists in the file header. Log and
            // continue on failure.
            if sqlite3_exec(dbPointer, "PRAGMA journal_mode = WAL", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to enable WAL on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .packages
                )
            }

            // #236 follow-up: SQLite-recommended `synchronous=NORMAL`
            // paired with WAL. Per-connection. See
            // https://www.sqlite.org/pragma.html#pragma_synchronous.
            if sqlite3_exec(dbPointer, "PRAGMA synchronous = NORMAL", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to set synchronous=NORMAL on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .packages
                )
            }

            // #236 follow-up: cap the WAL sidecar at 64 MB so
            // pathological reader-starvation cases don't grow the
            // file without bound. Default is -1 (unlimited).
            if sqlite3_exec(dbPointer, "PRAGMA journal_size_limit = 67108864", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to set journal_size_limit on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .packages
                )
            }

            // #864: turn on foreign-key enforcement so the schema's
            // declared `ON DELETE CASCADE` relationships (package_files
            // → package_metadata, package_symbols → package_files,
            // package_files_fts → package_files) actually fire when
            // a re-run wipes a package before re-inserting. SQLite
            // ships with `foreign_keys = OFF` per connection by
            // default; the indexer's wipe-then-insert path issues a
            // `DELETE FROM package_metadata WHERE owner = ? AND repo
            // = ?` and relies on the cascade to clear dependent rows
            // — without this PRAGMA, every re-run leaks ~1.4M orphan
            // `package_symbols` rows that inflate counts, slow scans,
            // and double-affect every enrichment pass.
            //
            // Per-connection, so set it for every open. Persisted in
            // the WAL header? No — `foreign_keys` is connection-
            // scoped, not stored in the file. That's why this lives
            // here next to the other open-time pragmas.
            if sqlite3_exec(dbPointer, "PRAGMA foreign_keys = ON", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to enable foreign_keys on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .packages
                )
            }

            database = dbPointer
        }

        private nonisolated func lastError(_ db: OpaquePointer?) -> String {
            guard let db else { return "no database" }
            return String(cString: sqlite3_errmsg(db))
        }

        // MARK: - Symbol extraction (visible for testing)

        /// Returns the file's content plus a case-split version of every identifier
        /// so camelCase and snake_case searches actually match. `makeHTTPRequest`
        /// becomes `makeHTTPRequest make HTTP Request`. `url_session_shared`
        /// becomes `url_session_shared url session shared`.
        static func symbolTokens(from source: String) -> String {
            guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*"#) else {
                return source
            }
            let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
            var pieces: [String] = []
            regex.enumerateMatches(in: source, options: [], range: nsRange) { match, _, _ in
                guard let match, let range = Range(match.range, in: source) else { return }
                let ident = String(source[range])
                pieces.append(ident)
                let split = splitIdentifier(ident)
                if split != ident {
                    pieces.append(split)
                }
            }
            return pieces.joined(separator: " ")
        }

        /// Split CamelCase / snake_case into space-separated words.
        /// `makeHTTPRequest` → `make HTTP Request`, `HTTPServer` → `HTTP Server`,
        /// `snake_case` → `snake case`.
        static func splitIdentifier(_ input: String) -> String {
            var result = input
            // lower -> upper
            result = result.replacingOccurrences(
                of: #"([a-z0-9])([A-Z])"#,
                with: "$1 $2",
                options: .regularExpression
            )
            // CAPS followed by Capitalized (`HTTPServer` → `HTTP Server`)
            result = result.replacingOccurrences(
                of: #"([A-Z])([A-Z][a-z])"#,
                with: "$1 $2",
                options: .regularExpression
            )
            // underscores
            result = result.replacingOccurrences(of: "_", with: " ")
            return result
        }

        /// Pull a title out of each file so SELECT results have something scannable.
        /// For markdown, that's the first heading. For Swift, it's the filename.
        /// For everything else, the filename.
        static func extractTitle(relpath: String, content: String) -> String {
            let filename = (relpath as NSString).lastPathComponent
            if filename.hasSuffix(".md") || filename.hasSuffix(".markdown") {
                for line in content.split(separator: "\n").prefix(50) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("# ") {
                        return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            return filename
        }
    }

    public enum PackageIndexError: Swift.Error, LocalizedError {
        case databaseNotInitialized
        case sqliteError(String)

        public var errorDescription: String? {
            switch self {
            case .databaseNotInitialized: return "package index database not initialized"
            case .sqliteError(let msg): return "SQLite error: \(msg)"
            }
        }
    }
}

/// SQLite3 convenience — the same constant SearchIndex uses, replicated here so this
/// file doesn't depend on Search/Index's private symbols.
// swiftlint:disable:next identifier_name
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
