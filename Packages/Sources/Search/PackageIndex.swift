import Core
import Foundation
import Shared
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
        // Bumped 1 → 2 in the #219 follow-up: added six availability
        // columns to `package_metadata` (`min_ios`, `min_macos`,
        // `min_tvos`, `min_watchos`, `min_visionos`,
        // `availability_source`) and one column to `package_files`
        // (`available_attrs_json`). Mirrors the SearchIndex docs_metadata
        // pattern (#192 sec. C). Existing v1 DBs migrate via
        // `ALTER TABLE ADD COLUMN`; fresh installs land them inline via
        // `createTables`. No destructive migration.
        public static let schemaVersion: Int32 = 2

        private var database: OpaquePointer?
        private let dbPath: URL
        private var isInitialized = false

        public init(
            dbPath: URL = Shared.Constants.defaultPackagesDatabase
        ) async throws {
            self.dbPath = dbPath
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
                source: String
            ) {
                self.deploymentTargets = deploymentTargets
                self.attributesByRelpath = attributesByRelpath
                self.source = source
            }
        }

        /// Index a single package end-to-end. Wipes any prior rows for the same
        /// (owner, repo) first so re-indexes converge cleanly without FTS5
        /// duplicate-row issues. All SQL runs in one transaction per package.
        public func index(
            resolved: Core.ResolvedPackage,
            extraction: Core.PackageArchiveExtractor.Result,
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
                try? execute("ROLLBACK")
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
            let packages = try Int(selectScalar("SELECT COUNT(*) FROM package_metadata"))
            let files = try Int(selectScalar("SELECT COUNT(*) FROM package_files"))
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
                UNIQUE(owner, repo)
            );

            CREATE INDEX IF NOT EXISTS idx_pkg_owner ON package_metadata(owner);
            CREATE INDEX IF NOT EXISTS idx_pkg_apple ON package_metadata(is_apple_official);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_ios ON package_metadata(min_ios);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_macos ON package_metadata(min_macos);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_tvos ON package_metadata(min_tvos);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_watchos ON package_metadata(min_watchos);
            CREATE INDEX IF NOT EXISTS idx_pkg_min_visionos ON package_metadata(min_visionos);

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
            resolved: Core.ResolvedPackage,
            extraction: Core.PackageArchiveExtractor.Result,
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
                min_ios, min_macos, min_tvos, min_watchos, min_visionos, availability_source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
            let parentsJSON = (try? JSONEncoder().encode(resolved.parents))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
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

            // Availability columns 13-18 (#219)
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

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
            return sqlite3_last_insert_rowid(database)
        }

        private func insertFile(
            packageId: Int64,
            resolved: Core.ResolvedPackage,
            file: Core.ExtractedFile,
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
                attrsJSON = (try? JSONEncoder().encode(encoded)).flatMap { String(data: $0, encoding: .utf8) }
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

    public enum PackageIndexError: Error, LocalizedError {
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
