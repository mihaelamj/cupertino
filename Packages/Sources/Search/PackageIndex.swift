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
        public static let schemaVersion: Int32 = 1

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

        /// Index a single package end-to-end. Wipes any prior rows for the same
        /// (owner, repo) first so re-indexes converge cleanly without FTS5
        /// duplicate-row issues. All SQL runs in one transaction per package.
        public func index(
            resolved: Core.ResolvedPackage,
            extraction: Core.PackageArchiveExtractor.Result,
            stars: Int? = nil,
            hostedDocumentationURL: URL? = nil
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
                    hostedDocumentationURL: hostedDocumentationURL
                )
                var bytes: Int64 = 0
                for file in extraction.files {
                    try insertFile(packageId: packageId, resolved: resolved, file: file)
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
            let packages = Int(try selectScalar("SELECT COUNT(*) FROM package_metadata"))
            let files = Int(try selectScalar("SELECT COUNT(*) FROM package_files"))
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
                UNIQUE(owner, repo)
            );

            CREATE INDEX IF NOT EXISTS idx_pkg_owner ON package_metadata(owner);
            CREATE INDEX IF NOT EXISTS idx_pkg_apple ON package_metadata(is_apple_official);

            CREATE TABLE IF NOT EXISTS package_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                package_id INTEGER NOT NULL,
                relpath TEXT NOT NULL,
                kind TEXT NOT NULL,
                module TEXT,
                size_bytes INTEGER NOT NULL,
                indexed_at INTEGER NOT NULL,
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
            hostedDocumentationURL: URL?
        ) throws -> Int64 {
            guard let database else { throw PackageIndexError.databaseNotInitialized }
            let sql = """
            INSERT INTO package_metadata (
                owner, repo, url, branch_used, stars, is_apple_official,
                tarball_bytes, total_bytes, fetched_at, cupertino_version,
                hosted_doc_url, parents_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw PackageIndexError.sqliteError(lastError(database))
            }
            return sqlite3_last_insert_rowid(database)
        }

        private func insertFile(
            packageId: Int64,
            resolved: Core.ResolvedPackage,
            file: Core.ExtractedFile
        ) throws {
            guard let database else { throw PackageIndexError.databaseNotInitialized }

            let insertPackageFileSQL = """
            INSERT INTO package_files (package_id, relpath, kind, module, size_bytes, indexed_at)
            VALUES (?, ?, ?, ?, ?, ?)
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
            for binder in binders { _ = binder(statement) }
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
        internal static func symbolTokens(from source: String) -> String {
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
        internal static func splitIdentifier(_ input: String) -> String {
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
        internal static func extractTitle(relpath: String, content: String) -> String {
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

// SQLite3 convenience — the same constant SearchIndex uses, replicated here so this
// file doesn't depend on Search/Index's private symbols.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
