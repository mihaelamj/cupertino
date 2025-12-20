import ASTIndexer
import Foundation
import SQLite3

// MARK: - Sample Index Database

// swiftlint:disable type_body_length file_length function_body_length

extension SampleIndex {
    /// SQLite FTS5-based database for sample code indexing and search
    public actor Database {
        /// Current schema version
        /// Version history:
        /// - 1: Initial schema (projects, files, projects_fts, files_fts)
        /// - 2: Added file_symbols, file_imports tables for SwiftSyntax AST indexing (#81)
        public static let schemaVersion: Int32 = 2

        private var database: OpaquePointer?
        private let dbPath: URL
        private var isInitialized = false

        public init(dbPath: URL = SampleIndex.defaultDatabasePath) async throws {
            self.dbPath = dbPath

            // Ensure directory exists
            let directory = dbPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            try await openDatabase()
            try await createTables()
            try await setSchemaVersion()
            isInitialized = true
        }

        /// Close database connection
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
                throw SampleIndex.Error.sqliteError("Failed to open database: \(errorMessage)")
            }

            database = dbPointer
        }

        private func setSchemaVersion() async throws {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
            }

            let sql = "PRAGMA user_version = \(Self.schemaVersion)"
            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }

            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
                throw SampleIndex.Error.sqliteError("Failed to set schema version: \(errorMessage)")
            }
        }

        private func createTables() async throws {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
            }

            let sql = """
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
                indexed_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_projects_title ON projects(title);

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
                FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_file_symbols_file ON file_symbols(file_id);
            CREATE INDEX IF NOT EXISTS idx_file_symbols_kind ON file_symbols(kind);
            CREATE INDEX IF NOT EXISTS idx_file_symbols_name ON file_symbols(name);
            CREATE INDEX IF NOT EXISTS idx_file_symbols_async ON file_symbols(is_async);

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
                throw SampleIndex.Error.sqliteError("Failed to create tables: \(errorMessage)")
            }
        }

        // MARK: - Project Indexing

        /// Index a sample project
        public func indexProject(_ project: Project) async throws {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
            }

            // Insert into projects table
            let sql = """
            INSERT OR REPLACE INTO projects
            (id, title, description, frameworks, readme, web_url, zip_filename, file_count, total_size, indexed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SampleIndex.Error.prepareFailed("Project insert: \(errorMessage)")
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

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SampleIndex.Error.insertFailed("Project insert: \(errorMessage)")
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
                throw SampleIndex.Error.databaseNotInitialized
            }

            // Insert into files table
            let sql = """
            INSERT OR REPLACE INTO files
            (project_id, path, filename, folder, extension, content, size)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SampleIndex.Error.prepareFailed("File insert: \(errorMessage)")
            }

            sqlite3_bind_text(statement, 1, (file.projectId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (file.path as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (file.filename as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (file.folder as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (file.fileExtension as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (file.content as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 7, Int64(file.size))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SampleIndex.Error.insertFailed("File insert: \(errorMessage)")
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
                throw SampleIndex.Error.databaseNotInitialized
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
            symbols: [ASTIndexer.ExtractedSymbol]
        ) async throws {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
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

        /// Index symbol into FTS table
        private func indexSymbolFTS(symbol: ASTIndexer.ExtractedSymbol) async throws {
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
            imports: [ASTIndexer.ExtractedImport]
        ) async throws {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
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
        public func searchProjects(
            query: String,
            framework: String? = nil,
            limit: Int = 20
        ) async throws -> [Project] {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw SampleIndex.Error.invalidQuery("Query cannot be empty")
            }

            // Sanitize query for FTS5
            let sanitizedQuery = query
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { "\"\($0)\"" }
                .joined(separator: " ")

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

            sql += " ORDER BY bm25(projects_fts) LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SampleIndex.Error.searchFailed("Project search: \(errorMessage)")
            }

            var paramIndex: Int32 = 1
            sqlite3_bind_text(statement, paramIndex, (sanitizedQuery as NSString).utf8String, -1, nil)
            paramIndex += 1

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

        /// Search result for file search
        public struct FileSearchResult: Sendable {
            public let projectId: String
            public let path: String
            public let filename: String
            public let snippet: String
            public let rank: Double
        }

        /// Search files by content
        public func searchFiles(
            query: String,
            projectId: String? = nil,
            fileExtension: String? = nil,
            limit: Int = 20
        ) async throws -> [FileSearchResult] {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw SampleIndex.Error.invalidQuery("Query cannot be empty")
            }

            // Sanitize for FTS5
            let sanitizedQuery = query
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .map { "\"\($0)\"" }
                .joined(separator: " ")

            var sql = """
            SELECT f.project_id, f.path, f.filename, snippet(files_fts, 3, '<b>', '</b>', '...', 50), bm25(files_fts)
            FROM files f
            JOIN files_fts fts ON f.project_id = fts.project_id AND f.path = fts.path
            WHERE files_fts MATCH ?
            """

            if projectId != nil {
                sql += " AND f.project_id = ?"
            }

            if fileExtension != nil {
                sql += " AND f.extension = ?"
            }

            sql += " ORDER BY bm25(files_fts) LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SampleIndex.Error.searchFailed("File search: \(errorMessage)")
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

            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [FileSearchResult] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let projectIdPtr = sqlite3_column_text(statement, 0),
                      let pathPtr = sqlite3_column_text(statement, 1),
                      let filenamePtr = sqlite3_column_text(statement, 2),
                      let snippetPtr = sqlite3_column_text(statement, 3)
                else {
                    continue
                }

                results.append(FileSearchResult(
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
        public func getProject(id: String) async throws -> Project? {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
            }

            let sql = """
            SELECT id, title, description, frameworks, readme, web_url, zip_filename,
                   file_count, total_size, indexed_at
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
                indexedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9)))
            )
        }

        // MARK: - Get File

        /// Get a file by project ID and path
        public func getFile(projectId: String, path: String) async throws -> File? {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
            }

            let sql = """
            SELECT project_id, path, filename, folder, extension, content, size
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

            return File(
                projectId: String(cString: projectIdPtr),
                path: String(cString: pathPtr),
                content: String(cString: contentPtr)
            )
        }

        // MARK: - List Files

        /// List all files in a project
        public func listFiles(projectId: String, folder: String? = nil) async throws -> [File] {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
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
                throw SampleIndex.Error.databaseNotInitialized
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
                throw SampleIndex.Error.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM projects;"

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
                throw SampleIndex.Error.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM files;"

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
                throw SampleIndex.Error.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM file_symbols;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// Get total import count (#81)
        public func importCount() async throws -> Int {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM file_imports;"

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
                throw SampleIndex.Error.databaseNotInitialized
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
                throw SampleIndex.Error.sqliteError("Failed to clear: \(errorMessage)")
            }
        }

        /// Delete a project and its files
        public func deleteProject(id: String) async throws {
            guard let database else {
                throw SampleIndex.Error.databaseNotInitialized
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

// swiftlint:enable type_body_length file_length function_body_length
