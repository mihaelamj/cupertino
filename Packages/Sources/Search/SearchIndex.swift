import ASTIndexer
import Foundation
import Shared
import SQLite3

// MARK: - Search Index

// swiftlint:disable type_body_length function_body_length function_parameter_count file_length
// Justification: This actor implements a complete SQLite FTS5 full-text search engine.
// It manages: database initialization, schema creation, document indexing with metadata,
// search query processing, statistics aggregation, and transaction management. The functions
// require multiple parameters to properly index documents with all metadata (id, title,
// framework, url, type, summary, content). Splitting would separate tightly-coupled SQL operations.
//            function_parameter_count (5 param limit, need 7 for complete document metadata)

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
        public static let schemaVersion: Int32 = 9

        private var database: OpaquePointer?
        private let dbPath: URL
        private var isInitialized = false

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
                throw SearchError.sqliteError("Failed to open database: \(errorMessage)")
            }

            database = dbPointer
        }

        private func getSchemaVersion() -> Int32 {
            guard let database else { return 0 }

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return sqlite3_column_int(statement, 0)
        }

        private func setSchemaVersion() async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = "PRAGMA user_version = \(Self.schemaVersion)"
            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }

            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
                throw SearchError.sqliteError("Failed to set schema version: \(errorMessage)")
            }
        }

        private func checkAndMigrateSchema() async throws {
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
                        "rm ~/.cupertino/search.db && cupertino save"
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
        }

        private func migrateToVersion7() async throws {
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

        private func migrateToVersion6() async throws {
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

        private func migrateToVersion4() async throws {
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

        private func migrateToVersion3() async throws {
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

        private func createTables() async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // FTS5 virtual table for full-text search
            // source: high-level category (apple-docs, swift-evolution, swift-org, swift-book)
            // framework: specific framework (swiftui, foundation, etc.) - same as source for non-apple-docs
            // language: programming language (swift, objc) - extracted from Apple's interfaceLanguage
            let sql = """
            CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
                uri,
                source,
                framework,
                language,
                title,
                content,
                summary,
                tokenize='porter unicode61'
            );

            CREATE TABLE IF NOT EXISTS docs_metadata (
                uri TEXT PRIMARY KEY,
                source TEXT NOT NULL DEFAULT 'apple-docs',
                framework TEXT NOT NULL,
                language TEXT NOT NULL DEFAULT 'swift',
                file_path TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                last_crawled INTEGER NOT NULL,
                word_count INTEGER NOT NULL,
                source_type TEXT DEFAULT 'apple',
                package_id INTEGER,
                json_data TEXT,
                -- Availability columns for efficient filtering (no JSON parsing needed)
                min_ios TEXT,           -- e.g., "13.0"
                min_macos TEXT,         -- e.g., "10.15"
                min_tvos TEXT,
                min_watchos TEXT,
                min_visionos TEXT,
                availability_source TEXT, -- 'api', 'parsed', 'inherited', 'derived'
                FOREIGN KEY (package_id) REFERENCES packages(id)
            );

            CREATE INDEX IF NOT EXISTS idx_source ON docs_metadata(source);
            CREATE INDEX IF NOT EXISTS idx_framework ON docs_metadata(framework);
            CREATE INDEX IF NOT EXISTS idx_language ON docs_metadata(language);
            CREATE INDEX IF NOT EXISTS idx_source_type ON docs_metadata(source_type);
            CREATE INDEX IF NOT EXISTS idx_min_ios ON docs_metadata(min_ios);
            CREATE INDEX IF NOT EXISTS idx_min_macos ON docs_metadata(min_macos);
            CREATE INDEX IF NOT EXISTS idx_min_tvos ON docs_metadata(min_tvos);
            CREATE INDEX IF NOT EXISTS idx_min_watchos ON docs_metadata(min_watchos);
            CREATE INDEX IF NOT EXISTS idx_min_visionos ON docs_metadata(min_visionos);

            -- Structured documentation fields (extracted from JSON for querying)
            CREATE TABLE IF NOT EXISTS docs_structured (
                uri TEXT PRIMARY KEY,
                url TEXT NOT NULL,
                title TEXT NOT NULL,
                kind TEXT,
                abstract TEXT,
                declaration TEXT,
                overview TEXT,
                module TEXT,
                platforms TEXT,
                conforms_to TEXT,
                inherited_by TEXT,
                conforming_types TEXT,
                attributes TEXT,  -- @MainActor, @Sendable, @available, etc. (comma-separated)
                FOREIGN KEY (uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_docs_kind ON docs_structured(kind);
            CREATE INDEX IF NOT EXISTS idx_docs_module ON docs_structured(module);
            CREATE INDEX IF NOT EXISTS idx_docs_attributes ON docs_structured(attributes);

            -- Framework aliases: maps identifier, import name, and display name
            -- identifier: appintents (lowercase, URL path, folder name)
            -- import_name: AppIntents (CamelCase, Swift import statement)
            -- display_name: App Intents (human-readable, from JSON module field)
            CREATE TABLE IF NOT EXISTS framework_aliases (
                identifier TEXT PRIMARY KEY,
                import_name TEXT NOT NULL,
                display_name TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_alias_import ON framework_aliases(import_name);
            CREATE INDEX IF NOT EXISTS idx_alias_display ON framework_aliases(display_name);

            CREATE TABLE IF NOT EXISTS packages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                owner TEXT NOT NULL,
                repository_url TEXT NOT NULL,
                documentation_url TEXT,
                stars INTEGER,
                last_updated INTEGER,
                is_apple_official INTEGER DEFAULT 0,
                description TEXT,
                UNIQUE(owner, name)
            );

            CREATE INDEX IF NOT EXISTS idx_package_owner ON packages(owner);
            CREATE INDEX IF NOT EXISTS idx_package_official ON packages(is_apple_official);

            CREATE TABLE IF NOT EXISTS package_dependencies (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                package_id INTEGER NOT NULL,
                depends_on_package_id INTEGER NOT NULL,
                version_requirement TEXT,
                FOREIGN KEY (package_id) REFERENCES packages(id),
                FOREIGN KEY (depends_on_package_id) REFERENCES packages(id),
                UNIQUE(package_id, depends_on_package_id)
            );

            CREATE INDEX IF NOT EXISTS idx_pkg_dep_package ON package_dependencies(package_id);
            CREATE INDEX IF NOT EXISTS idx_pkg_dep_depends ON package_dependencies(depends_on_package_id);

            CREATE VIRTUAL TABLE IF NOT EXISTS sample_code_fts USING fts5(
                url,
                framework,
                title,
                description,
                tokenize='porter unicode61'
            );

            CREATE TABLE IF NOT EXISTS sample_code_metadata (
                url TEXT PRIMARY KEY,
                framework TEXT NOT NULL,
                zip_filename TEXT NOT NULL,
                web_url TEXT NOT NULL,
                last_indexed INTEGER,
                -- Availability columns (derived from framework)
                min_ios TEXT,
                min_macos TEXT,
                min_tvos TEXT,
                min_watchos TEXT,
                min_visionos TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_sample_framework ON sample_code_metadata(framework);
            CREATE INDEX IF NOT EXISTS idx_sample_min_ios ON sample_code_metadata(min_ios);
            CREATE INDEX IF NOT EXISTS idx_sample_min_macos ON sample_code_metadata(min_macos);
            CREATE INDEX IF NOT EXISTS idx_sample_min_tvos ON sample_code_metadata(min_tvos);
            CREATE INDEX IF NOT EXISTS idx_sample_min_watchos ON sample_code_metadata(min_watchos);
            CREATE INDEX IF NOT EXISTS idx_sample_min_visionos ON sample_code_metadata(min_visionos);

            -- Code examples embedded in documentation pages
            CREATE TABLE IF NOT EXISTS doc_code_examples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                doc_uri TEXT NOT NULL,
                code TEXT NOT NULL,
                language TEXT DEFAULT 'swift',
                position INTEGER DEFAULT 0,
                FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri)
            );

            CREATE INDEX IF NOT EXISTS idx_code_doc_uri ON doc_code_examples(doc_uri);
            CREATE INDEX IF NOT EXISTS idx_code_language ON doc_code_examples(language);

            -- FTS for searching inside code examples
            CREATE VIRTUAL TABLE IF NOT EXISTS doc_code_fts USING fts5(
                code,
                tokenize='unicode61'
            );

            -- Symbols extracted from Swift code via SwiftSyntax AST (#81)
            CREATE TABLE IF NOT EXISTS doc_symbols (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                doc_uri TEXT NOT NULL,
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
                FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_doc_symbols_uri ON doc_symbols(doc_uri);
            CREATE INDEX IF NOT EXISTS idx_doc_symbols_kind ON doc_symbols(kind);
            CREATE INDEX IF NOT EXISTS idx_doc_symbols_name ON doc_symbols(name);
            CREATE INDEX IF NOT EXISTS idx_doc_symbols_async ON doc_symbols(is_async);

            -- FTS for symbol name search
            CREATE VIRTUAL TABLE IF NOT EXISTS doc_symbols_fts USING fts5(
                name,
                signature,
                attributes,
                conformances,
                tokenize='unicode61'
            );

            -- Imports extracted from code examples (#81)
            CREATE TABLE IF NOT EXISTS doc_imports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                doc_uri TEXT NOT NULL,
                module_name TEXT NOT NULL,
                line INTEGER NOT NULL,
                is_exported INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_doc_imports_uri ON doc_imports(doc_uri);
            CREATE INDEX IF NOT EXISTS idx_doc_imports_module ON doc_imports(module_name);
            """

            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }

            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
                throw SearchError.sqliteError("Failed to create tables: \(errorMessage)")
            }
        }

        // MARK: - Package Indexing

        /// Index a Swift package
        public func indexPackage(
            owner: String,
            name: String,
            repositoryURL: String,
            description: String?,
            stars: Int,
            isAppleOfficial: Bool,
            lastUpdated: String?
        ) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            INSERT OR REPLACE INTO packages
            (name, owner, repository_url, documentation_url, stars, is_apple_official, description, last_updated)
            VALUES (?, ?, ?, NULL, ?, ?, ?, ?)
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Package insert: \(errorMessage)")
            }

            sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (owner as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (repositoryURL as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 4, Int32(stars))
            sqlite3_bind_int(statement, 5, isAppleOfficial ? 1 : 0)

            if let description {
                sqlite3_bind_text(statement, 6, (description as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 6)
            }

            if let lastUpdated {
                // Try to parse the date and store as timestamp
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: lastUpdated) {
                    sqlite3_bind_int64(statement, 7, Int64(date.timeIntervalSince1970))
                } else {
                    sqlite3_bind_null(statement, 7)
                }
            } else {
                sqlite3_bind_null(statement, 7)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Package insert: \(errorMessage)")
            }
        }

        // MARK: - Sample Code Indexing

        /// Index a sample code entry with optional availability
        public func indexSampleCode(
            url: String,
            framework: String,
            title: String,
            description: String,
            zipFilename: String,
            webURL: String,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Insert into FTS5 table
            let ftsSql = """
            INSERT OR REPLACE INTO sample_code_fts (url, framework, title, description)
            VALUES (?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, ftsSql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Sample code FTS insert: \(errorMessage)")
            }

            sqlite3_bind_text(statement, 1, (url as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (framework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (description as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Sample code FTS insert: \(errorMessage)")
            }

            // Insert metadata with availability
            let metaSql = """
            INSERT OR REPLACE INTO sample_code_metadata \
            (url, framework, zip_filename, web_url, last_indexed, \
            min_ios, min_macos, min_tvos, min_watchos, min_visionos) \
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var metaStatement: OpaquePointer?
            defer { sqlite3_finalize(metaStatement) }

            guard sqlite3_prepare_v2(database, metaSql, -1, &metaStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Sample code metadata insert: \(errorMessage)")
            }

            sqlite3_bind_text(metaStatement, 1, (url as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 2, (framework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 3, (zipFilename as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 4, (webURL as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(metaStatement, 5, Int64(Date().timeIntervalSince1970))
            bindOptionalText(metaStatement, 6, minIOS)
            bindOptionalText(metaStatement, 7, minMacOS)
            bindOptionalText(metaStatement, 8, minTvOS)
            bindOptionalText(metaStatement, 9, minWatchOS)
            bindOptionalText(metaStatement, 10, minVisionOS)

            guard sqlite3_step(metaStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Sample code metadata insert: \(errorMessage)")
            }
        }

        /// Look up availability for a framework from indexed docs
        public func getFrameworkAvailability(framework: String) async -> FrameworkAvailability {
            guard let database else {
                return .empty
            }

            // Query the framework root document for availability
            let sql = """
            SELECT min_ios, min_macos, min_tvos, min_watchos, min_visionos
            FROM docs_metadata
            WHERE framework = ? AND min_ios IS NOT NULL
            LIMIT 1;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return .empty
            }

            sqlite3_bind_text(statement, 1, (framework.lowercased() as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return .empty
            }

            let minIOS = sqlite3_column_text(statement, 0).map { String(cString: $0) }
            let minMacOS = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let minTvOS = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let minWatchOS = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            let minVisionOS = sqlite3_column_text(statement, 4).map { String(cString: $0) }

            return FrameworkAvailability(
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS
            )
        }

        // MARK: - Doc Code Examples Indexing

        /// Index code examples from a documentation page
        public func indexCodeExamples(
            docUri: String,
            codeExamples: [(code: String, language: String)]
        ) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Delete existing code examples for this doc
            let deleteSql = "DELETE FROM doc_code_examples WHERE doc_uri = ?;"
            var deleteStmt: OpaquePointer?
            defer { sqlite3_finalize(deleteStmt) }

            if sqlite3_prepare_v2(database, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStmt, 1, (docUri as NSString).utf8String, -1, nil)
                _ = sqlite3_step(deleteStmt)
            }

            // Insert each code example
            let insertSql = """
            INSERT INTO doc_code_examples (doc_uri, code, language, position)
            VALUES (?, ?, ?, ?);
            """

            for (index, example) in codeExamples.enumerated() {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }

                guard sqlite3_prepare_v2(database, insertSql, -1, &statement, nil) == SQLITE_OK else {
                    continue
                }

                sqlite3_bind_text(statement, 1, (docUri as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (example.code as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (example.language as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 4, Int32(index))

                _ = sqlite3_step(statement)

                // Also insert into FTS for code search
                let ftsSql = "INSERT INTO doc_code_fts (rowid, code) VALUES (last_insert_rowid(), ?);"
                var ftsStmt: OpaquePointer?
                if sqlite3_prepare_v2(database, ftsSql, -1, &ftsStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(ftsStmt, 1, (example.code as NSString).utf8String, -1, nil)
                    _ = sqlite3_step(ftsStmt)
                    sqlite3_finalize(ftsStmt)
                }
            }
        }

        /// Search code examples
        public func searchCodeExamples(
            query: String,
            limit: Int = 20
        ) async throws -> [(docUri: String, code: String, language: String)] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            SELECT e.doc_uri, e.code, e.language
            FROM doc_code_examples e
            JOIN doc_code_fts f ON e.rowid = f.rowid
            WHERE doc_code_fts MATCH ?
            LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Code search prepare failed")
            }

            sqlite3_bind_text(statement, 1, (query as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var results: [(docUri: String, code: String, language: String)] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let docUri = String(cString: sqlite3_column_text(statement, 0))
                let code = String(cString: sqlite3_column_text(statement, 1))
                let language = String(cString: sqlite3_column_text(statement, 2))
                results.append((docUri: docUri, code: code, language: language))
            }

            return results
        }

        /// Get code examples count
        public func codeExamplesCount() async throws -> Int {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM doc_code_examples;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// Search sample code - optionally checks for local files in sampleCodeDirectory
        public func searchSampleCode(
            query: String,
            framework: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit,
            sampleCodeDirectory: URL? = nil
        ) async throws -> [Search.SampleCodeResult] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw SearchError.invalidQuery("Query cannot be empty")
            }

            var sql = """
            SELECT
                f.url,
                f.framework,
                f.title,
                f.description,
                m.zip_filename,
                m.web_url,
                bm25(sample_code_fts) as rank
            FROM sample_code_fts f
            JOIN sample_code_metadata m ON f.url = m.url
            WHERE sample_code_fts MATCH ?
            """

            if framework != nil {
                sql += " AND f.framework = ?"
            }

            sql += " ORDER BY rank LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Sample code search prepare failed: \(errorMessage)")
            }

            // Bind parameters
            sqlite3_bind_text(statement, 1, (query as NSString).utf8String, -1, nil)

            if let framework {
                sqlite3_bind_text(statement, 2, (framework as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 3, Int32(limit))
            } else {
                sqlite3_bind_int(statement, 2, Int32(limit))
            }

            // Execute and collect results
            var results: [Search.SampleCodeResult] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let urlPtr = sqlite3_column_text(statement, 0),
                      let frameworkPtr = sqlite3_column_text(statement, 1),
                      let titlePtr = sqlite3_column_text(statement, 2),
                      let descriptionPtr = sqlite3_column_text(statement, 3),
                      let zipFilenamePtr = sqlite3_column_text(statement, 4),
                      let webURLPtr = sqlite3_column_text(statement, 5)
                else {
                    continue
                }

                let url = String(cString: urlPtr)
                let framework = String(cString: frameworkPtr)
                let title = String(cString: titlePtr)
                let description = String(cString: descriptionPtr)
                let zipFilename = String(cString: zipFilenamePtr)
                let webURL = String(cString: webURLPtr)
                let rank = sqlite3_column_double(statement, 6)

                // Check if local file exists
                var localPath: String?
                var hasLocalFile = false
                if let sampleCodeDir = sampleCodeDirectory {
                    let localFileURL = sampleCodeDir.appendingPathComponent(zipFilename)
                    if FileManager.default.fileExists(atPath: localFileURL.path) {
                        localPath = localFileURL.path
                        hasLocalFile = true
                    }
                }

                results.append(
                    Search.SampleCodeResult(
                        url: url,
                        framework: framework,
                        title: title,
                        description: description,
                        zipFilename: zipFilename,
                        webURL: webURL,
                        localPath: localPath,
                        hasLocalFile: hasLocalFile,
                        rank: rank
                    )
                )
            }

            return results
        }

        // MARK: - Indexing

        /// Index a single document
        /// - Parameters:
        ///   - uri: Document URI
        ///   - source: High-level source category (apple-docs, swift-evolution, swift-org, swift-book)
        ///   - framework: Specific framework (swiftui, foundation, etc.) - nil for non-apple-docs sources
        ///   - language: Programming language (swift, objc) - defaults to swift if not provided
        ///   - title: Document title
        ///   - content: Full document content
        ///   - filePath: Path to source file
        ///   - contentHash: SHA256 hash of content
        ///   - lastCrawled: Crawl timestamp
        ///   - sourceType: Legacy source type field (deprecated, use source instead)
        ///   - packageId: Optional package ID for package docs
        ///   - jsonData: Optional JSON representation of document
        public func indexDocument(
            uri: String,
            source: String,
            framework: String?,
            language: String? = nil,
            title: String,
            content: String,
            filePath: String,
            contentHash: String,
            lastCrawled: Date,
            sourceType: String = Shared.Constants.Database.defaultSourceTypeApple,
            packageId: Int? = nil,
            jsonData: String? = nil,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil,
            availabilitySource: String? = nil
        ) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Extract summary (first 500 chars, stop at sentence)
            let summary = extractSummary(from: content)
            let wordCount = content.split(separator: " ").count

            // For non-apple-docs sources, framework can be nil or empty
            let effectiveFramework = framework ?? ""

            // Determine language with heuristics fallback
            let effectiveLanguage = language ?? detectLanguage(from: content)

            // Insert into FTS5 table (db should be deleted before full re-index)
            let ftsSql = """
            INSERT INTO docs_fts (uri, source, framework, language, title, content, summary)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, ftsSql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("FTS insert: \(errorMessage)")
            }

            sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (source as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (effectiveFramework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (effectiveLanguage as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 7, (summary as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("FTS insert: \(errorMessage)")
            }

            // Create minimal JSON wrapper if no jsonData provided
            let finalJsonData: String
            if let jsonData {
                finalJsonData = jsonData
            } else {
                // Create minimal JSON for markdown-only content
                let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
                let minimalJSON = """
                {"title":"\(escapedTitle)","url":"\(uri)","rawMarkdown":null,\
                "source":"\(source)","framework":"\(effectiveFramework)"}
                """
                finalJsonData = minimalJSON
            }

            // Insert metadata with JSON data and availability
            let metaSql = """
            INSERT OR REPLACE INTO docs_metadata \
            (uri, source, framework, language, file_path, content_hash, last_crawled, word_count, \
            source_type, package_id, json_data, min_ios, min_macos, min_tvos, min_watchos, \
            min_visionos, availability_source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var metaStatement: OpaquePointer?
            defer { sqlite3_finalize(metaStatement) }

            guard sqlite3_prepare_v2(database, metaSql, -1, &metaStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Metadata insert: \(errorMessage)")
            }

            sqlite3_bind_text(metaStatement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 2, (source as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 3, (effectiveFramework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 4, (effectiveLanguage as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 5, (filePath as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 6, (contentHash as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(metaStatement, 7, Int64(lastCrawled.timeIntervalSince1970))
            sqlite3_bind_int(metaStatement, 8, Int32(wordCount))
            sqlite3_bind_text(metaStatement, 9, (sourceType as NSString).utf8String, -1, nil)

            if let packageId {
                sqlite3_bind_int(metaStatement, 10, Int32(packageId))
            } else {
                sqlite3_bind_null(metaStatement, 10)
            }

            sqlite3_bind_text(metaStatement, 11, (finalJsonData as NSString).utf8String, -1, nil)

            // Bind availability columns
            bindOptionalText(metaStatement, 12, minIOS)
            bindOptionalText(metaStatement, 13, minMacOS)
            bindOptionalText(metaStatement, 14, minTvOS)
            bindOptionalText(metaStatement, 15, minWatchOS)
            bindOptionalText(metaStatement, 16, minVisionOS)
            bindOptionalText(metaStatement, 17, availabilitySource)

            guard sqlite3_step(metaStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Metadata insert: \(errorMessage)")
            }
        }

        // MARK: - Protocol-Based Indexing

        /// Index a source item using the appropriate SourceIndexer
        /// This provides a unified interface for indexing content from any source.
        /// - Parameters:
        ///   - item: The source item to index
        ///   - extractSymbols: Whether to extract and index AST symbols (default: true)
        /// - Throws: SearchError if indexing fails
        public func indexItem(_ item: SourceItem, extractSymbols: Bool = true) async throws {
            // Get the indexer for this source
            guard let indexer = IndexerRegistry.indexer(for: item.source) else {
                // Fall back to generic indexing if no specific indexer
                try await indexDocument(
                    uri: item.uri,
                    source: item.source,
                    framework: item.framework,
                    language: item.language,
                    title: item.title,
                    content: item.content,
                    filePath: item.filePath,
                    contentHash: item.contentHash,
                    lastCrawled: item.lastCrawled,
                    sourceType: item.sourceType,
                    packageId: item.packageId,
                    jsonData: item.jsonData,
                    minIOS: item.minIOS,
                    minMacOS: item.minMacOS,
                    minTvOS: item.minTvOS,
                    minWatchOS: item.minWatchOS,
                    minVisionOS: item.minVisionOS,
                    availabilitySource: item.availabilitySource
                )
                return
            }

            // Validate the item
            guard indexer.validate(item) else {
                throw SearchError.invalidQuery("Item failed validation for source: \(item.source)")
            }

            // Preprocess the item
            let processedItem = indexer.preprocess(item)

            // Index the document
            try await indexDocument(
                uri: processedItem.uri,
                source: processedItem.source,
                framework: processedItem.framework,
                language: processedItem.language,
                title: processedItem.title,
                content: processedItem.content,
                filePath: processedItem.filePath,
                contentHash: processedItem.contentHash,
                lastCrawled: processedItem.lastCrawled,
                sourceType: processedItem.sourceType,
                packageId: processedItem.packageId,
                jsonData: processedItem.jsonData,
                minIOS: processedItem.minIOS,
                minMacOS: processedItem.minMacOS,
                minTvOS: processedItem.minTvOS,
                minWatchOS: processedItem.minWatchOS,
                minVisionOS: processedItem.minVisionOS,
                availabilitySource: processedItem.availabilitySource
            )

            // Extract and index AST symbols if enabled
            if extractSymbols {
                let extracted = indexer.extractCode(from: processedItem)
                if !extracted.symbols.isEmpty {
                    try await indexDocSymbols(
                        docUri: processedItem.uri,
                        symbols: extracted.symbols
                    )
                }
                if !extracted.imports.isEmpty {
                    try await indexDocImports(
                        docUri: processedItem.uri,
                        imports: extracted.imports
                    )
                }
            }

            // Postprocess
            indexer.postprocess(processedItem)
        }

        /// Batch index multiple source items
        /// - Parameters:
        ///   - items: Array of source items to index
        ///   - extractSymbols: Whether to extract AST symbols
        ///   - progress: Optional progress callback (itemIndex, totalItems)
        /// - Returns: Number of successfully indexed items
        @discardableResult
        public func indexItems(
            _ items: [SourceItem],
            extractSymbols: Bool = true,
            progress: ((Int, Int) -> Void)? = nil
        ) async throws -> Int {
            var successCount = 0

            for (index, item) in items.enumerated() {
                do {
                    try await indexItem(item, extractSymbols: extractSymbols)
                    successCount += 1
                } catch {
                    // Log error but continue with other items
                    // In production, could collect errors and report at end
                }
                progress?(index + 1, items.count)
            }

            return successCount
        }

        /// Extract optimized FTS content based on document kind
        /// Core types get focused content (title, abstract, overview) without member noise
        /// Members get title + abstract + declaration for quick matching
        private func extractOptimizedContent(from page: StructuredDocumentationPage) -> String {
            let kind = page.inferredKind
            var parts: [String] = []

            switch kind {
            case .protocol, .class, .struct, .enum, .typeAlias:
                // Core types: high-signal content only
                // Repeat title multiple times to boost title matching in BM25
                parts.append(page.title)
                parts.append(page.title)
                parts.append(page.title)

                if let abstract = page.abstract {
                    parts.append(abstract)
                }

                if let declaration = page.declaration?.code {
                    parts.append(declaration)
                }

                if let overview = page.overview {
                    // Take first 2000 chars of overview to avoid noise
                    let truncated = String(overview.prefix(2000))
                    parts.append(truncated)
                }

            case .method, .property, .operator, .macro:
                // Members: focused on identity and usage
                parts.append(page.title)
                parts.append(page.title)

                if let abstract = page.abstract {
                    parts.append(abstract)
                }

                if let declaration = page.declaration?.code {
                    parts.append(declaration)
                }

            case .article, .tutorial, .collection:
                // Articles: use full content for comprehensive search
                if let raw = page.rawMarkdown {
                    return raw
                }
                return page.markdown

            case .unknown, .framework, .function:
                // Unknown/framework/function: use raw content as fallback
                if let raw = page.rawMarkdown {
                    return raw
                }
                return page.markdown
            }

            return parts.joined(separator: "\n\n")
        }

        /// Index a structured documentation page with full JSON data
        /// - Parameters:
        ///   - uri: Document URI
        ///   - source: High-level source category (apple-docs, swift-evolution, swift-org, swift-book)
        ///   - framework: Specific framework (swiftui, foundation, etc.) - for apple-docs only
        ///   - page: The structured documentation page
        ///   - jsonData: JSON representation of the page
        public func indexStructuredDocument(
            uri: String,
            source: String,
            framework: String,
            page: StructuredDocumentationPage,
            jsonData: String,
            overrideMinIOS: String? = nil,
            overrideMinMacOS: String? = nil,
            overrideMinTvOS: String? = nil,
            overrideMinWatchOS: String? = nil,
            overrideMinVisionOS: String? = nil,
            overrideAvailabilitySource: String? = nil
        ) async throws {
            // Register framework alias if module is available
            if let module = page.module, !module.isEmpty {
                try await registerFrameworkAlias(identifier: framework, displayName: module)
            }

            // First, index the basic document (FTS + metadata with json_data)
            // Extract optimized content based on document kind to improve BM25 ranking
            var content = extractOptimizedContent(from: page)

            // Append @attributes to content for FTS searchability
            // This allows searching for @MainActor, @Sendable, @available etc.
            let attributes = page.extractedAttributes
            if !attributes.isEmpty {
                content += "\n\n" + attributes.joined(separator: " ")
            }

            let summary = extractSummary(from: content)
            let wordCount = content.split(separator: " ").count

            // Get language from page or use heuristics
            let effectiveLanguage = page.language ?? detectLanguage(from: content)

            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Insert into FTS5 table (db should be deleted before full re-index)
            let ftsSql = """
            INSERT INTO docs_fts (uri, source, framework, language, title, content, summary)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, ftsSql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("FTS insert: \(errorMessage)")
            }

            sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (source as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (framework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (effectiveLanguage as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (page.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 7, (summary as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("FTS insert: \(errorMessage)")
            }

            // Extract availability from JSON data, with optional overrides
            let jsonAvailability = extractAvailabilityFromJSON(jsonData)
            let finalIOS = overrideMinIOS ?? jsonAvailability.iOS
            let finalMacOS = overrideMinMacOS ?? jsonAvailability.macOS
            let finalTvOS = overrideMinTvOS ?? jsonAvailability.tvOS
            let finalWatchOS = overrideMinWatchOS ?? jsonAvailability.watchOS
            let finalVisionOS = overrideMinVisionOS ?? jsonAvailability.visionOS
            let finalSource = overrideAvailabilitySource ?? jsonAvailability.source

            // Insert metadata with json_data and availability columns
            let metaSql = """
            INSERT OR REPLACE INTO docs_metadata \
            (uri, source, framework, language, file_path, content_hash, last_crawled, word_count, \
            source_type, json_data, min_ios, min_macos, min_tvos, min_watchos, min_visionos, \
            availability_source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var metaStatement: OpaquePointer?
            defer { sqlite3_finalize(metaStatement) }

            guard sqlite3_prepare_v2(database, metaSql, -1, &metaStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Metadata insert: \(errorMessage)")
            }

            sqlite3_bind_text(metaStatement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 2, (source as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 3, (framework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 4, (effectiveLanguage as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 5, (page.url.absoluteString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 6, (page.contentHash as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(metaStatement, 7, Int64(page.crawledAt.timeIntervalSince1970))
            sqlite3_bind_int(metaStatement, 8, Int32(wordCount))
            sqlite3_bind_text(metaStatement, 9, (page.source.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 10, (jsonData as NSString).utf8String, -1, nil)

            // Bind availability columns (use final values with overrides)
            bindOptionalText(metaStatement, 11, finalIOS)
            bindOptionalText(metaStatement, 12, finalMacOS)
            bindOptionalText(metaStatement, 13, finalTvOS)
            bindOptionalText(metaStatement, 14, finalWatchOS)
            bindOptionalText(metaStatement, 15, finalVisionOS)
            bindOptionalText(metaStatement, 16, finalSource)

            guard sqlite3_step(metaStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Metadata insert: \(errorMessage)")
            }

            // Insert structured fields for querying
            // swiftlint:disable:next line_length
            let structSql = "INSERT OR REPLACE INTO docs_structured (uri, url, title, kind, abstract, declaration, overview, module, platforms, conforms_to, inherited_by, conforming_types, attributes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"

            var structStatement: OpaquePointer?
            defer { sqlite3_finalize(structStatement) }

            guard sqlite3_prepare_v2(database, structSql, -1, &structStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Structured insert: \(errorMessage)")
            }

            sqlite3_bind_text(structStatement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(structStatement, 2, (page.url.absoluteString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(structStatement, 3, (page.title as NSString).utf8String, -1, nil)
            // Use inferredKind to correctly classify ~16,500 docs currently marked as "unknown"
            sqlite3_bind_text(structStatement, 4, (page.inferredKind.rawValue as NSString).utf8String, -1, nil)

            if let abstract = page.abstract {
                sqlite3_bind_text(structStatement, 5, (abstract as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 5)
            }

            if let declaration = page.declaration {
                sqlite3_bind_text(structStatement, 6, (declaration.code as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 6)
            }

            if let overview = page.overview {
                sqlite3_bind_text(structStatement, 7, (overview as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 7)
            }

            if let module = page.module {
                sqlite3_bind_text(structStatement, 8, (module as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 8)
            }

            if let platforms = page.platforms {
                let value = (platforms.joined(separator: ",") as NSString).utf8String
                sqlite3_bind_text(structStatement, 9, value, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 9)
            }

            if let conformsTo = page.conformsTo {
                let value = (conformsTo.joined(separator: ",") as NSString).utf8String
                sqlite3_bind_text(structStatement, 10, value, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 10)
            }

            if let inheritedBy = page.inheritedBy {
                let value = (inheritedBy.joined(separator: ",") as NSString).utf8String
                sqlite3_bind_text(structStatement, 11, value, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 11)
            }

            if let conformingTypes = page.conformingTypes {
                let value = (conformingTypes.joined(separator: ",") as NSString).utf8String
                sqlite3_bind_text(structStatement, 12, value, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 12)
            }

            // Store @attributes for filtering (reuse variable from FTS content extraction above)
            if !attributes.isEmpty {
                let value = (attributes.joined(separator: ",") as NSString).utf8String
                sqlite3_bind_text(structStatement, 13, value, -1, nil)
            } else {
                sqlite3_bind_null(structStatement, 13)
            }

            guard sqlite3_step(structStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Structured insert: \(errorMessage)")
            }

            // Extract symbols from declaration using SwiftSyntax (#81)
            if let declaration = page.declaration?.code {
                let extractor = ASTIndexer.SwiftSourceExtractor()
                let result = extractor.extract(from: declaration)
                if !result.symbols.isEmpty {
                    try await indexDocSymbols(docUri: uri, symbols: result.symbols)
                }
                if !result.imports.isEmpty {
                    try await indexDocImports(docUri: uri, imports: result.imports)
                }
            }
        }

        // MARK: - Symbol Indexing (#81)

        /// Index symbols extracted from Swift code in documentation
        private func indexDocSymbols(
            docUri: String,
            symbols: [ASTIndexer.ExtractedSymbol]
        ) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            INSERT INTO doc_symbols
            (doc_uri, name, kind, line, column, signature, is_async, is_throws,
             is_public, is_static, attributes, conformances, generic_params)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            for symbol in symbols {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }

                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    continue
                }

                sqlite3_bind_text(statement, 1, (docUri as NSString).utf8String, -1, nil)
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

                let attributesStr = symbol.attributes.isEmpty
                    ? nil : symbol.attributes.joined(separator: ",")
                let conformancesStr = symbol.conformances.isEmpty
                    ? nil : symbol.conformances.joined(separator: ",")
                let genericParamsStr = symbol.genericParameters.isEmpty
                    ? nil : symbol.genericParameters.joined(separator: ",")

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
                try await indexDocSymbolFTS(symbol: symbol)
            }
        }

        /// Index symbol into FTS table
        private func indexDocSymbolFTS(symbol: ASTIndexer.ExtractedSymbol) async throws {
            guard let database else { return }

            let sql = """
            INSERT INTO doc_symbols_fts (name, signature, attributes, conformances)
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

        /// Index imports extracted from Swift code in documentation
        private func indexDocImports(
            docUri: String,
            imports: [ASTIndexer.ExtractedImport]
        ) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            INSERT INTO doc_imports (doc_uri, module_name, line, is_exported)
            VALUES (?, ?, ?, ?);
            """

            for imp in imports {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }

                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    continue
                }

                sqlite3_bind_text(statement, 1, (docUri as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (imp.moduleName as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 3, Int32(imp.line))
                sqlite3_bind_int(statement, 4, imp.isExported ? 1 : 0)

                _ = sqlite3_step(statement)
            }
        }

        /// Get full JSON data for a document
        public func getDocumentJSON(uri: String) async throws -> String? {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = "SELECT json_data FROM docs_metadata WHERE uri = ?;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }

            sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            guard let text = sqlite3_column_text(statement, 0) else {
                return nil
            }

            return String(cString: text)
        }

        /// Search by kind (protocol, class, struct, etc.)
        public func searchByKind(
            kind: String,
            framework: String? = nil,
            limit: Int = 50
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            var sql = """
            SELECT s.uri, s.title, f.framework, f.summary, m.word_count, m.file_path, m.source
            FROM docs_structured s
            JOIN docs_fts f ON s.uri = f.uri
            JOIN docs_metadata m ON s.uri = m.uri
            WHERE s.kind = ?
            """

            if framework != nil {
                sql += " AND f.framework = ?"
            }

            sql += " ORDER BY s.title LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Kind search prepare failed")
            }

            sqlite3_bind_text(statement, 1, (kind as NSString).utf8String, -1, nil)

            var paramIndex: Int32 = 2
            if let framework {
                sqlite3_bind_text(statement, paramIndex, (framework as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let uri = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let framework = String(cString: sqlite3_column_text(statement, 2))
                let summary = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let wordCount = Int(sqlite3_column_int(statement, 4))
                let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                    ?? Shared.Constants.SourcePrefix.appleDocs

                results.append(Search.Result(
                    uri: uri,
                    source: source,
                    framework: framework,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: 0.0
                ))
            }

            return results
        }

        /// Search protocols that a type conforms to
        public func searchConformsTo(
            protocolName: String,
            limit: Int = 50
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            SELECT s.uri, s.title, f.framework, f.summary, m.word_count, m.file_path, m.source
            FROM docs_structured s
            JOIN docs_fts f ON s.uri = f.uri
            JOIN docs_metadata m ON s.uri = m.uri
            WHERE s.conforms_to LIKE ?
            ORDER BY s.title LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Conforms search prepare failed")
            }

            sqlite3_bind_text(statement, 1, ("%\(protocolName)%" as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let uri = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let framework = String(cString: sqlite3_column_text(statement, 2))
                let summary = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let wordCount = Int(sqlite3_column_int(statement, 4))
                let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                    ?? Shared.Constants.SourcePrefix.appleDocs

                results.append(Search.Result(
                    uri: uri,
                    source: source,
                    framework: framework,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: 0.0
                ))
            }

            return results
        }

        /// Search by module name
        public func searchByModule(
            module: String,
            kind: String? = nil,
            limit: Int = 50
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            var sql = """
            SELECT s.uri, s.title, f.framework, f.summary, m.word_count, m.file_path, m.source
            FROM docs_structured s
            JOIN docs_fts f ON s.uri = f.uri
            JOIN docs_metadata m ON s.uri = m.uri
            WHERE s.module = ?
            """

            if kind != nil {
                sql += " AND s.kind = ?"
            }

            sql += " ORDER BY s.title LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Module search prepare failed")
            }

            sqlite3_bind_text(statement, 1, (module as NSString).utf8String, -1, nil)

            var paramIndex: Int32 = 2
            if let kind {
                sqlite3_bind_text(statement, paramIndex, (kind as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let uri = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let framework = String(cString: sqlite3_column_text(statement, 2))
                let summary = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let wordCount = Int(sqlite3_column_int(statement, 4))
                let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                    ?? Shared.Constants.SourcePrefix.appleDocs

                results.append(Search.Result(
                    uri: uri,
                    source: source,
                    framework: framework,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: 0.0
                ))
            }

            return results
        }

        /// Search for types inherited by a given type
        public func searchInheritedBy(
            typeName: String,
            limit: Int = 50
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            SELECT s.uri, s.title, f.framework, f.summary, m.word_count, m.file_path, m.source
            FROM docs_structured s
            JOIN docs_fts f ON s.uri = f.uri
            JOIN docs_metadata m ON s.uri = m.uri
            WHERE s.inherited_by LIKE ?
            ORDER BY s.title LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Inherited search prepare failed")
            }

            sqlite3_bind_text(statement, 1, ("%\(typeName)%" as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let uri = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let framework = String(cString: sqlite3_column_text(statement, 2))
                let summary = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let wordCount = Int(sqlite3_column_int(statement, 4))
                let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                    ?? Shared.Constants.SourcePrefix.appleDocs

                results.append(Search.Result(
                    uri: uri,
                    source: source,
                    framework: framework,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: 0.0
                ))
            }

            return results
        }

        /// Search for conforming types (types that conform to a protocol)
        public func searchConformingTypes(
            protocolName: String,
            limit: Int = 50
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            SELECT s.uri, s.title, f.framework, f.summary, m.word_count, m.file_path, m.source
            FROM docs_structured s
            JOIN docs_fts f ON s.uri = f.uri
            JOIN docs_metadata m ON s.uri = m.uri
            WHERE s.conforming_types LIKE ?
            ORDER BY s.title LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Conforming types search prepare failed")
            }

            sqlite3_bind_text(statement, 1, ("%\(protocolName)%" as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let uri = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let framework = String(cString: sqlite3_column_text(statement, 2))
                let summary = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let wordCount = Int(sqlite3_column_int(statement, 4))
                let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                    ?? Shared.Constants.SourcePrefix.appleDocs

                results.append(Search.Result(
                    uri: uri,
                    source: source,
                    framework: framework,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: 0.0
                ))
            }

            return results
        }

        /// Search in declaration text
        public func searchByDeclaration(
            pattern: String,
            kind: String? = nil,
            limit: Int = 50
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            var sql = """
            SELECT s.uri, s.title, f.framework, f.summary, m.word_count, m.file_path, m.source
            FROM docs_structured s
            JOIN docs_fts f ON s.uri = f.uri
            JOIN docs_metadata m ON s.uri = m.uri
            WHERE s.declaration LIKE ?
            """

            if kind != nil {
                sql += " AND s.kind = ?"
            }

            sql += " ORDER BY s.title LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Declaration search prepare failed")
            }

            sqlite3_bind_text(statement, 1, ("%\(pattern)%" as NSString).utf8String, -1, nil)

            var paramIndex: Int32 = 2
            if let kind {
                sqlite3_bind_text(statement, paramIndex, (kind as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let uri = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let framework = String(cString: sqlite3_column_text(statement, 2))
                let summary = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let wordCount = Int(sqlite3_column_int(statement, 4))
                let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                    ?? Shared.Constants.SourcePrefix.appleDocs

                results.append(Search.Result(
                    uri: uri,
                    source: source,
                    framework: framework,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: 0.0
                ))
            }

            return results
        }

        /// Search by platform (iOS, macOS, etc.)
        public func searchByPlatform(
            platform: String,
            kind: String? = nil,
            limit: Int = 50
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            var sql = """
            SELECT s.uri, s.title, f.framework, f.summary, m.word_count, m.file_path, m.source
            FROM docs_structured s
            JOIN docs_fts f ON s.uri = f.uri
            JOIN docs_metadata m ON s.uri = m.uri
            WHERE s.platforms LIKE ?
            """

            if kind != nil {
                sql += " AND s.kind = ?"
            }

            sql += " ORDER BY s.title LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Platform search prepare failed")
            }

            sqlite3_bind_text(statement, 1, ("%\(platform)%" as NSString).utf8String, -1, nil)

            var paramIndex: Int32 = 2
            if let kind {
                sqlite3_bind_text(statement, paramIndex, (kind as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let uri = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let framework = String(cString: sqlite3_column_text(statement, 2))
                let summary = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let wordCount = Int(sqlite3_column_int(statement, 4))
                let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                    ?? Shared.Constants.SourcePrefix.appleDocs

                results.append(Search.Result(
                    uri: uri,
                    source: source,
                    framework: framework,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: 0.0
                ))
            }

            return results
        }

        // MARK: - Searching

        /// Known source prefixes that should be treated as source filters when detected in query.
        /// See Shared.Constants.SourcePrefix for available prefixes.
        private static let knownSourcePrefixes = Shared.Constants.SourcePrefix.allPrefixes

        /// Extract source prefix from query if present.
        /// - Returns: (detectedSource, remainingQuery)
        /// - Example: "swift-evolution actors" -> ("swift-evolution", "actors")
        private func extractSourcePrefix(_ query: String) -> (source: String?, remainingQuery: String) {
            let lowercased = query.lowercased()

            for prefix in Self.knownSourcePrefixes where lowercased.hasPrefix(prefix) {
                // Check if it's followed by whitespace or end of string
                let afterPrefix = query.dropFirst(prefix.count)
                if afterPrefix.isEmpty || afterPrefix.first?.isWhitespace == true {
                    let remaining = String(afterPrefix).trimmingCharacters(in: .whitespaces)
                    return (prefix, remaining)
                }
            }

            return (nil, query)
        }

        /// Known Swift attributes that can be searched with or without @ prefix
        /// Based on attributes actually present in Apple documentation declarations
        /// TODO(#81): When SwiftSyntax AST indexing is implemented, this list should be
        /// replaced with attributes extracted directly from parsed declarations
        private static let knownAttributes: Set<String> = [
            // Concurrency
            "MainActor", "Sendable", "preconcurrency",
            // Memory/copying
            "NSCopying", "frozen",
            // Objective-C interop
            "objc", "objcMembers", "nonobjc", "IBAction", "IBOutlet",
            // Function attributes
            "discardableResult", "warn_unqualified_access", "inlinable", "usableFromInline",
            // Type attributes
            "dynamicMemberLookup", "dynamicCallable", "propertyWrapper", "resultBuilder",
            // SwiftUI builders
            "ViewBuilder", "ToolbarContentBuilder", "CommandsBuilder", "SceneBuilder",
            // Macros
            "freestanding", "attached",
            // Availability
            "backDeployed", "available",
            // SwiftUI property wrappers (for future use)
            "State", "Binding", "Environment", "Published",
            "ObservedObject", "StateObject", "EnvironmentObject",
            "AppStorage", "SceneStorage", "FocusState",
            // SwiftData
            "Model", "Query", "Attribute", "Relationship",
        ]

        /// Extract @attribute patterns from query for filtering
        /// - Parameter query: User's search query (e.g., "@MainActor View" or "MainActor View")
        /// - Returns: Tuple of (attributes to filter, query for FTS with @ stripped)
        /// - Example: "@MainActor View" -> (["@MainActor"], "MainActor View")
        /// - Example: "MainActor View" -> (["@MainActor"], "MainActor View")
        private func extractAttributeFilters(_ query: String) -> (attributes: [String], ftsQuery: String) {
            var attributes: [String] = []
            var ftsQuery = query

            // First, handle explicit @Attribute patterns (including those with arguments)
            let explicitPattern = #"@[A-Z][a-zA-Z0-9]*(?:\([^)]*\))?"#
            if let regex = try? NSRegularExpression(pattern: explicitPattern) {
                let range = NSRange(query.startIndex..., in: query)
                let matches = regex.matches(in: query, range: range)

                for match in matches.reversed() {
                    if let matchRange = Range(match.range, in: query) {
                        let attribute = String(query[matchRange])
                        attributes.insert(attribute, at: 0)

                        // Strip @ from FTS query but keep the name for searchability
                        let withoutAt = attribute.dropFirst()
                        ftsQuery.replaceSubrange(matchRange, with: withoutAt)
                    }
                }
            }

            // Then, check for known attribute names without @ prefix
            let words = ftsQuery.components(separatedBy: .whitespaces)
            for word in words {
                let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
                if Self.knownAttributes.contains(trimmed), !attributes.contains("@\(trimmed)") {
                    attributes.append("@\(trimmed)")
                }
            }

            return (attributes, ftsQuery)
        }

        /// Sanitize a search query for FTS5
        /// - Splits on whitespace and hyphens (except for known framework prefixes)
        /// - Quotes each term to avoid FTS5 operator interpretation
        /// - Example: "concurrency actors" -> "\"concurrency\" \"actors\""
        private func sanitizeFTS5Query(_ query: String) -> String {
            let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-"))
            let terms = query
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { "\"\($0)\"" }
            return terms.joined(separator: " ")
        }

        /// Search documents by query with optional source, framework, and language filters
        /// If query starts with a known source prefix (e.g., "swift-book"), it's extracted as a filter
        /// - Parameters:
        ///   - query: Search query (may include source prefix like "swift-evolution actors")
        ///   - source: Optional source filter (apple-docs, swift-evolution, etc.)
        ///   - framework: Optional framework filter (swiftui, foundation, etc. - only for apple-docs)
        ///   - language: Optional language filter (swift, objc)
        ///   - limit: Maximum number of results
        // swiftlint:disable:next cyclomatic_complexity
        public func search(
            query: String,
            source: String? = nil,
            framework: String? = nil,
            language: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit,
            includeArchive: Bool = false,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw SearchError.invalidQuery("Query cannot be empty")
            }

            // Detect query intent for source boosting (#81)
            // This analyzes the query to determine what kind of content the user wants
            let queryIntent = detectQueryIntent(query)

            // Extract source prefix from query if no explicit source provided
            let (detectedSource, remainingQuery) = source == nil
                ? extractSourcePrefix(query)
                : (nil, query)

            // Use explicit source or detected source
            let effectiveSource = source ?? detectedSource

            // Resolve framework input to identifier (supports "appintents", "AppIntents", "App Intents")
            let effectiveFramework: String?
            if let framework {
                effectiveFramework = try await resolveFrameworkIdentifier(framework)
            } else {
                effectiveFramework = nil
            }

            // Check if user explicitly requested archive
            let archiveRequested = effectiveSource == "apple-archive"

            // Use remaining query after extracting source prefix
            let queryToSearch = remainingQuery.isEmpty ? query : remainingQuery

            // Extract @attribute patterns from query (handles "@MainActor" and "MainActor")
            // Note: Attributes are used for boosting via symbol search, not hard filtering
            let (_, queryForFTS) = extractAttributeFilters(queryToSearch)
            let sanitizedQuery = sanitizeFTS5Query(queryForFTS)

            var sql = """
            SELECT
                f.uri,
                f.source,
                f.framework,
                f.title,
                f.summary,
                m.file_path,
                m.word_count,
                bm25(docs_fts) as rank,
                COALESCE(s.kind, 'unknown') as kind,
                m.min_ios,
                m.min_macos,
                m.min_tvos,
                m.min_watchos,
                m.min_visionos
            FROM docs_fts f
            JOIN docs_metadata m ON f.uri = m.uri
            LEFT JOIN docs_structured s ON f.uri = s.uri
            WHERE docs_fts MATCH ?
            """

            if effectiveSource != nil {
                sql += " AND f.source = ?"
            } else if !includeArchive, !archiveRequested {
                // Exclude apple-archive by default unless explicitly requested or includeArchive is true
                sql += " AND f.source != 'apple-archive'"
            }
            if effectiveFramework != nil {
                sql += " AND f.framework = ?"
            }
            if language != nil {
                sql += " AND f.language = ?"
            }

            // Note: Attribute patterns (e.g., "@MainActor") are used for BOOSTING via symbol search,
            // not hard filtering. Hard filtering would return 0 results for macros like @Observable
            // that aren't in doc_symbols.attributes. Symbol boosting happens later in this function.

            // Normalize empty strings to nil (treat as no filter)
            let effectiveMinIOS = minIOS?.isEmpty == true ? nil : minIOS
            let effectiveMinMacOS = minMacOS?.isEmpty == true ? nil : minMacOS
            let effectiveMinTvOS = minTvOS?.isEmpty == true ? nil : minTvOS
            let effectiveMinWatchOS = minWatchOS?.isEmpty == true ? nil : minWatchOS
            let effectiveMinVisionOS = minVisionOS?.isEmpty == true ? nil : minVisionOS

            // Add platform version filters (uses indexed columns for NULL filtering)
            // Note: We filter IS NOT NULL at SQL level (uses index), then do proper
            // version comparison in memory since SQL CAST doesn't handle "10.13" vs "10.2" correctly
            if effectiveMinIOS != nil {
                sql += " AND m.min_ios IS NOT NULL"
            }
            if effectiveMinMacOS != nil {
                sql += " AND m.min_macos IS NOT NULL"
            }
            if effectiveMinTvOS != nil {
                sql += " AND m.min_tvos IS NOT NULL"
            }
            if effectiveMinWatchOS != nil {
                sql += " AND m.min_watchos IS NOT NULL"
            }
            if effectiveMinVisionOS != nil {
                sql += " AND m.min_visionos IS NOT NULL"
            }

            // Fetch significantly more results so title/kind boosts can surface buried gems
            // View protocol has poor BM25 but exact title match should bring it to top
            let fetchLimit = min(limit * 20, 1000) // Fetch 20x more, max 1000
            sql += " ORDER BY rank LIMIT ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Prepare failed: \(errorMessage)")
            }

            // Bind parameters (use sanitized query for FTS5)
            var paramIndex: Int32 = 1
            sqlite3_bind_text(statement, paramIndex, (sanitizedQuery as NSString).utf8String, -1, nil)
            paramIndex += 1

            if let effectiveSource {
                sqlite3_bind_text(statement, paramIndex, (effectiveSource as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            if let effectiveFramework {
                sqlite3_bind_text(statement, paramIndex, (effectiveFramework as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            if let language {
                sqlite3_bind_text(statement, paramIndex, (language as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            // Note: Attribute filters removed - boosting via symbol search instead
            // Note: Platform version filters use IS NOT NULL (no binding needed)
            // Proper version comparison happens in memory after fetch
            sqlite3_bind_int(statement, paramIndex, Int32(fetchLimit))

            // Execute and collect results
            // Column order: uri(0), source(1), framework(2), title(3), summary(4), file_path(5),
            //               word_count(6), rank(7), kind(8), min_ios(9), min_macos(10),
            //               min_tvos(11), min_watchos(12), min_visionos(13)
            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let uriPtr = sqlite3_column_text(statement, 0),
                      let sourcePtr = sqlite3_column_text(statement, 1),
                      let frameworkPtr = sqlite3_column_text(statement, 2),
                      let titlePtr = sqlite3_column_text(statement, 3),
                      let summaryPtr = sqlite3_column_text(statement, 4),
                      let filePathPtr = sqlite3_column_text(statement, 5),
                      let kindPtr = sqlite3_column_text(statement, 8)
                else {
                    continue
                }

                let uri = String(cString: uriPtr)
                let source = String(cString: sourcePtr)
                let framework = String(cString: frameworkPtr)
                let title = String(cString: titlePtr)
                let summary = String(cString: summaryPtr)
                let filePath = String(cString: filePathPtr)
                let wordCount = Int(sqlite3_column_int(statement, 6))
                let bm25Rank = sqlite3_column_double(statement, 7)

                // Read availability from dedicated columns (no JSON parsing needed)
                let miniOSPtr = sqlite3_column_text(statement, 9)
                let minMacOSPtr = sqlite3_column_text(statement, 10)
                let minTvOSPtr = sqlite3_column_text(statement, 11)
                let minWatchOSPtr = sqlite3_column_text(statement, 12)
                let minVisionOSPtr = sqlite3_column_text(statement, 13)

                // Build availability array from columns
                var availabilityItems: [SearchPlatformAvailability] = []
                if let ptr = miniOSPtr {
                    availabilityItems.append(SearchPlatformAvailability(
                        name: "iOS",
                        introducedAt: String(cString: ptr),
                        deprecated: false,
                        unavailable: false,
                        beta: false
                    ))
                }
                if let ptr = minMacOSPtr {
                    availabilityItems.append(SearchPlatformAvailability(
                        name: "macOS",
                        introducedAt: String(cString: ptr),
                        deprecated: false,
                        unavailable: false,
                        beta: false
                    ))
                }
                if let ptr = minTvOSPtr {
                    availabilityItems.append(SearchPlatformAvailability(
                        name: "tvOS",
                        introducedAt: String(cString: ptr),
                        deprecated: false,
                        unavailable: false,
                        beta: false
                    ))
                }
                if let ptr = minWatchOSPtr {
                    availabilityItems.append(SearchPlatformAvailability(
                        name: "watchOS",
                        introducedAt: String(cString: ptr),
                        deprecated: false,
                        unavailable: false,
                        beta: false
                    ))
                }
                if let ptr = minVisionOSPtr {
                    availabilityItems.append(SearchPlatformAvailability(
                        name: "visionOS",
                        introducedAt: String(cString: ptr),
                        deprecated: false,
                        unavailable: false,
                        beta: false
                    ))
                }
                let availability: [SearchPlatformAvailability]? = availabilityItems.isEmpty ? nil : availabilityItems
                let rawKind = String(cString: kindPtr)

                // Infer kind when unknown using multiple signals
                let kind: String = {
                    if rawKind != "unknown" && !rawKind.isEmpty {
                        return rawKind
                    }

                    // SIGNAL 1: URL depth analysis
                    // Shallow paths like /documentation/swiftui/view → core type
                    // Deep paths like /documentation/swiftui/view/body-8kl5o → member
                    let pathComponents = uri.components(separatedBy: "/")
                        .filter { !$0.isEmpty && $0 != "documentation" }
                    let urlDepth = pathComponents.count

                    // SIGNAL 2: Title pattern analysis
                    let titleLower = title.lowercased()
                    let titleTrimmed = title.trimmingCharacters(in: .whitespaces)

                    // Method patterns: contains parentheses like foo(_:) or init(from:)
                    if title.contains("(_:") || title.contains("(") && title.contains(":)") {
                        return "method"
                    }

                    // Operator patterns: starts with operator symbols
                    if titleTrimmed.hasPrefix("+") || titleTrimmed.hasPrefix("-") ||
                        titleTrimmed.hasPrefix("*") || titleTrimmed.hasPrefix("/") ||
                        titleTrimmed.hasPrefix("==") || titleTrimmed.hasPrefix("!=") ||
                        titleTrimmed.hasPrefix("<") || titleTrimmed.hasPrefix(">") {
                        return "method" // Operators are methods
                    }

                    // Property patterns: camelCase starting lowercase, single word
                    let words = title.components(separatedBy: .whitespaces)
                    if words.count == 1 {
                        let first = titleTrimmed.first
                        if let first, first.isLowercase, !title.contains("(") {
                            return "property"
                        }
                    }

                    // Protocol suffix pattern
                    if titleLower.hasSuffix("protocol") || titleLower.hasSuffix("delegate") {
                        return "protocol"
                    }

                    // SIGNAL 3: URL depth heuristic for Apple docs
                    // /framework/type → depth 2 = core type
                    // /framework/type/member → depth 3+ = member
                    if uri.hasPrefix("apple-docs://") {
                        if urlDepth <= 2 {
                            // Short path + CamelCase title = likely core type
                            if let first = titleTrimmed.first, first.isUppercase, !title.contains("(") {
                                return "struct" // Default to struct for unknown core types
                            }
                        } else if urlDepth >= 3 {
                            // Deep path = likely member
                            if let first = titleTrimmed.first, first.isLowercase {
                                return "property"
                            }
                        }
                    }

                    // SIGNAL 4: Word count as quality signal
                    // Core types typically have rich documentation
                    if wordCount > 500, urlDepth <= 2 {
                        if let first = titleTrimmed.first, first.isUppercase {
                            return "struct" // Rich docs + short path + CamelCase = core type
                        }
                    }

                    return "unknown"
                }()

                // Apply kind-based ranking multiplier
                // BM25 scores are NEGATIVE (lower = better match)
                // Core types (protocol, class, struct, framework) get boosted (divide to make smaller/better)
                // Member docs (property, method) get penalized (multiply to make larger/worse)
                let kindMultiplier: Double = {
                    switch kind {
                    case "protocol", "class", "struct", "framework":
                        return 0.5 // Divide to boost (smaller negative = better rank)
                    case "property", "method":
                        return 2.0 // Multiply to penalize (larger negative = worse rank)
                    default:
                        return 1.0
                    }
                }()

                // Apply source-based ranking multiplier with intent-aware boosting (#81)
                // Uses queryIntent to determine which sources should be prioritized
                typealias SourcePrefix = Shared.Constants.SourcePrefix
                let sourceMultiplier: Double = {
                    // Penalize release notes - they match almost every query but rarely what user wants
                    if uri.contains("release-notes") {
                        return 2.5 // Strong penalty - release notes pollute general searches
                    }

                    // Convert source string to SearchSource for intent matching
                    let searchSource = SearchSource(rawValue: source)

                    // Check if this source is boosted for the detected intent
                    let isIntentBoosted = searchSource.map { queryIntent.boostedSources.contains($0) } ?? false

                    // Get SourceProperties for quality-based scoring (#81)
                    // Uses empirical data from SourceRegistry (single source of truth)
                    let sourceProps = searchSource.flatMap { SourceRegistry.properties(for: $0.rawValue) }

                    // Calculate base multiplier from SourceProperties or fallback to static values
                    let baseMultiplier: Double = {
                        if let props = sourceProps {
                            // Use searchQuality to create multiplier
                            // searchQuality 1.0 → multiplier 0.5 (2x boost)
                            // searchQuality 0.5 → multiplier 1.0 (no boost)
                            // searchQuality 0.0 → multiplier 1.5 (penalty)
                            return 1.5 - (props.searchQuality * 1.0)
                        }
                        // Fallback for unknown sources
                        if source == SourcePrefix.appleDocs {
                            return 1.0 // Baseline - modern docs
                        } else if source == SourcePrefix.appleArchive {
                            return 1.5 // Slight penalty - archived guides
                        } else if source == SourcePrefix.swiftEvolution {
                            return 1.3 // Slight penalty - proposals
                        } else if source == SourcePrefix.swiftBook || source == SourcePrefix.swiftOrg {
                            return 0.9 // Slight boost - official Swift docs
                        } else {
                            return 1.0
                        }
                    }()

                    // Apply intent-aware scoring using SourceProperties.scoreFor(intent:)
                    // This gives a weighted score based on how well the source fits the intent
                    let intentScore: Double = {
                        guard let props = sourceProps else { return 1.0 }
                        // scoreFor returns 0.0-1.0, higher = better fit
                        // Convert to multiplier: 1.0 → 0.6 (boost), 0.5 → 0.8, 0.0 → 1.0
                        return 1.0 - (props.scoreFor(intent: queryIntent) * 0.4)
                    }()

                    // Combine: base quality * intent fit * intent boost
                    var multiplier = baseMultiplier * intentScore
                    if isIntentBoosted {
                        multiplier *= 0.5 // Additional 2x boost for intent-matched sources
                    }
                    return multiplier
                }()

                // Apply intelligent title and query matching heuristics
                let combinedBoost: Double = {
                    // Use original query for semantic matching (not sanitized)
                    let queryWords = query.lowercased()
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty && $0.count > 1 } // Filter noise words

                    let titleLower = title.lowercased()
                    let titleWords = titleLower.components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }

                    var boost = 1.0

                    // FRAMEWORK ROOT BOOST: Framework root page match (#81)
                    // If user types "SwiftUI" and this is the SwiftUI framework page = definitely what they want
                    // Framework roots often have title "X | Apple Developer Documentation" and kind "article"
                    // Detect by: URI pattern "apple-docs://X/documentation_X" where X matches query
                    let queryLowerJoined = queryWords.joined(separator: " ")

                    // Extract framework from URI: apple-docs://swiftui/documentation_swiftui → swiftui
                    let uriLower = uri.lowercased()
                    let isFrameworkRoot: Bool = {
                        // Pattern: apple-docs://FRAMEWORK/documentation_FRAMEWORK
                        if uriLower.hasPrefix("apple-docs://") {
                            let parts = uriLower
                                .replacingOccurrences(of: "apple-docs://", with: "")
                                .components(separatedBy: "/")
                            if parts.count == 2,
                               parts[1] == "documentation_\(parts[0])" {
                                // This is a framework root page, check if query matches
                                return parts[0] == queryLowerJoined
                            }
                        }
                        return false
                    }()

                    let titleWithoutSuffix = titleLower
                        .replacingOccurrences(of: " | apple developer documentation", with: "")
                        .trimmingCharacters(in: .whitespaces)

                    if isFrameworkRoot {
                        boost *= 0.01 // 100x boost for framework root page match
                    } else if kind == "framework", titleWithoutSuffix == queryLowerJoined {
                        boost *= 0.05 // 20x boost for explicit framework kind match
                    }

                    // HEURISTIC 1: Short query exact title match (user knows what they want)
                    // "View" searching for "View" protocol = almost certainly what they want
                    if queryWords.count <= 3, titleLower == queryWords.joined(separator: " ") {
                        boost *= 0.05 // 20x boost - user typed exact name
                    }
                    // First word exact match (very strong signal)
                    else if !titleWords.isEmpty, !queryWords.isEmpty, titleWords[0] == queryWords[0] {
                        boost *= 0.15 // 6-7x boost - title starts with query word
                    }
                    // All query words in title
                    else if queryWords.allSatisfy({ titleLower.contains($0) }) {
                        boost *= 0.3 // 3x boost - all terms match
                    }
                    // Any query word in title
                    else if queryWords.contains(where: { titleLower.contains($0) }) {
                        boost *= 0.6 // ~1.5x boost - partial match
                    }

                    // HEURISTIC: Penalize nested types when searching for parent type
                    // Problem: "Text" query returns "Text.Scale" before "Text"
                    // Reason: "Text.Scale" starts with "Text" and gets the 0.15 boost
                    // Solution: If query has no dot but title does, apply penalty
                    let queryLower = query.lowercased()
                    if !queryLower.contains("."), titleLower.contains(".") {
                        boost *= 2.0 // Penalty: nested types should rank below parent types
                    }

                    // HEURISTIC 2: Query pattern analysis
                    let queryText = query.lowercased()

                    // "X protocol" pattern → boost protocols more
                    if queryText.contains("protocol"), kind == "protocol" {
                        boost *= 0.4 // Extra 2.5x for protocols when user asks for protocols
                    }
                    // "X class" pattern → boost classes
                    else if queryText.contains("class"), kind == "class" {
                        boost *= 0.4
                    }
                    // "X struct" pattern → boost structs
                    else if queryText.contains("struct"), kind == "struct" {
                        boost *= 0.4
                    }

                    // HEURISTIC 3: Context-aware kind boosting
                    // Single-word queries with framework filter = looking for core type
                    if queryWords.count == 1, framework == "swiftui" {
                        switch kind {
                        case "protocol", "class", "struct":
                            boost *= 0.5 // Additional 2x for core types with short queries
                        default:
                            break
                        }
                    }

                    // HEURISTIC 4: Penalize overly verbose titles for short queries
                    // If query is short but title is long, it's probably not what user wants
                    if queryWords.count <= 2, title.count > 50 {
                        boost *= 1.3 // Slight penalty for verbose titles vs short queries
                    }

                    return boost
                }()

                // CRITICAL: BM25 scores are negative, LOWER = better
                // To boost (improve rank), we need to make MORE negative
                // So we DIVIDE by multipliers (smaller multiplier = larger negative number)
                let adjustedRank = bm25Rank / (kindMultiplier * sourceMultiplier * combinedBoost)

                results.append(
                    Search.Result(
                        uri: uri,
                        source: source,
                        framework: framework,
                        title: title,
                        summary: summary,
                        filePath: filePath,
                        wordCount: wordCount,
                        rank: adjustedRank,
                        availability: availability
                    )
                )
            }

            // Re-sort by adjusted rank (lower BM25 = better)
            results.sort { $0.rank < $1.rank }

            // (#81) Boost results that also match in doc_symbols_fts
            // This enables semantic search for @Observable, async, Sendable, etc.
            let symbolMatchURIs = try await searchSymbolsForURIs(query: sanitizedQuery, limit: 500)
            if !symbolMatchURIs.isEmpty {
                results = results.map { result in
                    if symbolMatchURIs.contains(result.uri) {
                        // Boost rank for symbol matches (BM25 is negative, lower = better)
                        return Search.Result(
                            id: result.id,
                            uri: result.uri,
                            source: result.source,
                            framework: result.framework,
                            title: result.title,
                            summary: result.summary,
                            filePath: result.filePath,
                            wordCount: result.wordCount,
                            rank: result.rank * 0.3, // 3x boost for symbol matches
                            availability: result.availability
                        )
                    }
                    return result
                }
                // Re-sort after symbol boosting
                results.sort { $0.rank < $1.rank }
            }

            // Apply platform version filters (proper semantic version comparison)
            // SQL already filtered for IS NOT NULL, now we do proper version compare
            if let effectiveMinIOS {
                results = results.filter { result in
                    guard let version = result.minimumiOS else { return false }
                    return Self.isVersion(version, lessThanOrEqualTo: effectiveMinIOS)
                }
            }
            if let effectiveMinMacOS {
                results = results.filter { result in
                    guard let version = result.minimumMacOS else { return false }
                    return Self.isVersion(version, lessThanOrEqualTo: effectiveMinMacOS)
                }
            }
            if let effectiveMinTvOS {
                results = results.filter { result in
                    guard let version = result.minimumTvOS else { return false }
                    return Self.isVersion(version, lessThanOrEqualTo: effectiveMinTvOS)
                }
            }
            if let effectiveMinWatchOS {
                results = results.filter { result in
                    guard let version = result.minimumWatchOS else { return false }
                    return Self.isVersion(version, lessThanOrEqualTo: effectiveMinWatchOS)
                }
            }
            if let effectiveMinVisionOS {
                results = results.filter { result in
                    guard let version = result.minimumVisionOS else { return false }
                    return Self.isVersion(version, lessThanOrEqualTo: effectiveMinVisionOS)
                }
            }

            // (#81) Ensure framework root page appears at top for single-word framework queries
            // This bypasses BM25 limitations for framework names like "SwiftUI", "Foundation", etc.
            // Only apply for apple-docs source or when no source filter is specified
            let shouldFetchFrameworkRoot = effectiveSource == nil ||
                effectiveSource == Shared.Constants.SourcePrefix.appleDocs
            if shouldFetchFrameworkRoot,
               let frameworkRoot = try await fetchFrameworkRoot(query: query) {
                // Remove duplicate if it exists in results
                results.removeAll { $0.uri == frameworkRoot.uri }
                // Insert at top
                results.insert(frameworkRoot, at: 0)
            }

            // (#81) Attach matching symbols to results that have them
            if !symbolMatchURIs.isEmpty {
                let symbolsByURI = try await fetchMatchingSymbols(query: sanitizedQuery, uris: symbolMatchURIs)
                results = results.map { result in
                    if let symbols = symbolsByURI[result.uri], !symbols.isEmpty {
                        return Search.Result(
                            id: result.id,
                            uri: result.uri,
                            source: result.source,
                            framework: result.framework,
                            title: result.title,
                            summary: result.summary,
                            filePath: result.filePath,
                            wordCount: result.wordCount,
                            rank: result.rank,
                            availability: result.availability,
                            matchedSymbols: symbols
                        )
                    }
                    return result
                }
            }

            // Trim to requested limit after applying boosts
            return Array(results.prefix(limit))
        }

        /// Fetch matching symbols for a set of document URIs (#81)
        /// Returns dictionary mapping URI to array of matched symbols
        private func fetchMatchingSymbols(query: String, uris: Set<String>) async throws -> [String: [MatchedSymbol]] {
            guard let database, !uris.isEmpty else { return [:] }

            // Strip FTS5 quotes from sanitized query for LIKE pattern
            let cleanQuery = query.replacingOccurrences(of: "\"", with: "")
            let likePattern = "%\(cleanQuery)%"

            // Build placeholders for IN clause
            let placeholders = uris.map { _ in "?" }.joined(separator: ", ")
            let sql = """
            SELECT doc_uri, kind, name, signature, is_async
            FROM doc_symbols
            WHERE doc_uri IN (\(placeholders))
              AND (name LIKE ? OR attributes LIKE ? OR conformances LIKE ? OR signature LIKE ?)
            ORDER BY doc_uri, name
            LIMIT 500;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return [:]
            }

            // Bind URI parameters
            var bindIndex: Int32 = 1
            for uri in uris {
                sqlite3_bind_text(statement, bindIndex, (uri as NSString).utf8String, -1, nil)
                bindIndex += 1
            }

            // Bind LIKE patterns
            sqlite3_bind_text(statement, bindIndex, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, bindIndex + 1, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, bindIndex + 2, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, bindIndex + 3, (likePattern as NSString).utf8String, -1, nil)

            var result: [String: [MatchedSymbol]] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let uriPtr = sqlite3_column_text(statement, 0),
                      let kindPtr = sqlite3_column_text(statement, 1),
                      let namePtr = sqlite3_column_text(statement, 2) else {
                    continue
                }

                let uri = String(cString: uriPtr)
                let kind = String(cString: kindPtr)
                let name = String(cString: namePtr)
                let signature = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                let isAsync = sqlite3_column_int(statement, 4) != 0

                let symbol = MatchedSymbol(kind: kind, name: name, signature: signature, isAsync: isAsync)
                result[uri, default: []].append(symbol)
            }

            // Limit symbols per document to top 3 for readability
            for (uri, symbols) in result {
                result[uri] = Array(symbols.prefix(3))
            }

            return result
        }

        /// Search doc_symbols and return matching document URIs (#81)
        /// Enables semantic search for @Observable, async, Sendable, MainActor, etc.
        private func searchSymbolsForURIs(query: String, limit: Int) async throws -> Set<String> {
            guard let database else { return [] }

            // Strip FTS5 quotes and trim whitespace for LIKE pattern
            let cleanQuery = query
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard cleanQuery.count >= 3 else { return [] }

            // Search doc_symbols directly using LIKE patterns
            // Matches in: symbol name, attributes (@Observable), conformances (Sendable), signature (async)
            let likePattern = "%\(cleanQuery)%"
            let sql = """
            SELECT DISTINCT doc_uri
            FROM doc_symbols
            WHERE name LIKE ?
               OR attributes LIKE ?
               OR conformances LIKE ?
               OR signature LIKE ?
            LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return [] // Fail silently - symbol search is optional enhancement
            }

            sqlite3_bind_text(statement, 1, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (likePattern as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 5, Int32(limit))

            var uris: Set<String> = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let uriPtr = sqlite3_column_text(statement, 0) {
                    uris.insert(String(cString: uriPtr))
                }
            }

            return uris
        }

        /// Fetch framework root page by exact query match (#81)
        /// If user searches "SwiftUI", directly fetch apple-docs://swiftui/documentation_swiftui
        /// This ensures framework roots always appear regardless of BM25 score
        private func fetchFrameworkRoot(query: String) async throws -> Search.Result? {
            guard let database else { return nil }

            // Only for single-word queries that could be framework names
            let queryLower = query.lowercased().trimmingCharacters(in: .whitespaces)
            guard !queryLower.contains(" "), queryLower.count >= 2 else { return nil }

            // Construct expected framework root URI
            let frameworkRootURI = "apple-docs://\(queryLower)/documentation_\(queryLower)"

            // Direct lookup by URI - join FTS for title/summary, metadata for availability
            let sql = """
            SELECT
                f.uri, f.source, f.framework, f.title, f.summary, m.file_path, m.word_count,
                m.min_ios, m.min_macos, m.min_tvos, m.min_watchos, m.min_visionos
            FROM docs_fts f
            JOIN docs_metadata m ON f.uri = m.uri
            WHERE f.uri = ?
            LIMIT 1;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }

            sqlite3_bind_text(statement, 1, (frameworkRootURI as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil // Framework root not found
            }

            // Extract result
            let uri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let source = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let summary = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            let wordCount = Int(sqlite3_column_int(statement, 6))

            // Build availability array from platform versions
            var availabilityArray: [SearchPlatformAvailability] = []
            if let ios = sqlite3_column_text(statement, 7).map({ String(cString: $0) }) {
                availabilityArray.append(SearchPlatformAvailability(name: "iOS", introducedAt: ios))
            }
            if let macos = sqlite3_column_text(statement, 8).map({ String(cString: $0) }) {
                availabilityArray.append(SearchPlatformAvailability(name: "macOS", introducedAt: macos))
            }
            if let tvos = sqlite3_column_text(statement, 9).map({ String(cString: $0) }) {
                availabilityArray.append(SearchPlatformAvailability(name: "tvOS", introducedAt: tvos))
            }
            if let watchos = sqlite3_column_text(statement, 10).map({ String(cString: $0) }) {
                availabilityArray.append(SearchPlatformAvailability(name: "watchOS", introducedAt: watchos))
            }
            if let visionos = sqlite3_column_text(statement, 11).map({ String(cString: $0) }) {
                availabilityArray.append(SearchPlatformAvailability(name: "visionOS", introducedAt: visionos))
            }

            // Return with best possible rank (most negative)
            return Search.Result(
                uri: uri,
                source: source,
                framework: framework.isEmpty ? queryLower : framework,
                title: title,
                summary: summary,
                filePath: filePath,
                wordCount: wordCount,
                rank: -1000.0, // Guaranteed top rank
                availability: availabilityArray.isEmpty ? nil : availabilityArray
            )
        }

        /// Compare semantic version strings (e.g., "10.13" vs "10.2")
        /// Returns true if lhs <= rhs (API introduced at or before target version)
        private static func isVersion(_ lhs: String, lessThanOrEqualTo rhs: String) -> Bool {
            let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
            let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }

            for idx in 0..<max(lhsComponents.count, rhsComponents.count) {
                let lhsValue = idx < lhsComponents.count ? lhsComponents[idx] : 0
                let rhsValue = idx < rhsComponents.count ? rhsComponents[idx] : 0

                if lhsValue < rhsValue { return true }
                if lhsValue > rhsValue { return false }
            }
            return true // Equal versions
        }

        // MARK: - Semantic Symbol Search (#81)

        /// Symbol search result with document context
        public struct SymbolSearchResult: Sendable {
            public let docUri: String
            public let docTitle: String
            public let framework: String
            public let symbolName: String
            public let symbolKind: String
            public let signature: String?
            public let attributes: String?
            public let conformances: String?
            public let isAsync: Bool
            public let isPublic: Bool
        }

        /// Search symbols by name pattern and optional filters
        /// - Parameters:
        ///   - query: Symbol name pattern (partial match)
        ///   - kind: Filter by symbol kind (struct, class, actor, enum, protocol, function, property)
        ///   - isAsync: Filter to async functions only
        ///   - framework: Filter by framework
        ///   - limit: Maximum results
        /// - Returns: Array of symbol search results with document context
        public func searchSymbols(
            query: String?,
            kind: String? = nil,
            isAsync: Bool? = nil,
            framework: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) async throws -> [SymbolSearchResult] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            var conditions: [String] = []
            var params: [Any] = []

            if let query, !query.isEmpty {
                conditions.append("s.name LIKE ?")
                params.append("%\(query)%")
            }

            if let kind, !kind.isEmpty {
                conditions.append("s.kind = ?")
                params.append(kind.lowercased())
            }

            if let isAsync, isAsync {
                conditions.append("s.is_async = 1")
            }

            if let framework, !framework.isEmpty {
                conditions.append("m.framework = ?")
                params.append(framework.lowercased())
            }

            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

            let sql = """
            SELECT DISTINCT
                s.doc_uri,
                f.title,
                COALESCE(m.framework, '') as framework,
                s.name,
                s.kind,
                s.signature,
                s.attributes,
                s.conformances,
                s.is_async,
                s.is_public
            FROM doc_symbols s
            JOIN docs_fts f ON s.doc_uri = f.uri
            LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
            \(whereClause)
            ORDER BY s.name
            LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Symbol search failed: \(errorMessage)")
            }

            var paramIndex: Int32 = 1
            for param in params {
                if let str = param as? String {
                    sqlite3_bind_text(statement, paramIndex, (str as NSString).utf8String, -1, nil)
                }
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [SymbolSearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                let isAsync = sqlite3_column_int(statement, 8) != 0
                let isPublic = sqlite3_column_int(statement, 9) != 0

                results.append(SymbolSearchResult(
                    docUri: docUri,
                    docTitle: docTitle,
                    framework: framework,
                    symbolName: symbolName,
                    symbolKind: symbolKind,
                    signature: signature,
                    attributes: attributes,
                    conformances: conformances,
                    isAsync: isAsync,
                    isPublic: isPublic
                ))
            }

            return results
        }

        /// Search for property wrapper usage
        /// - Parameters:
        ///   - wrapper: Property wrapper name (with or without @)
        ///   - framework: Filter by framework
        ///   - limit: Maximum results
        /// - Returns: Array of symbol results containing the wrapper
        public func searchPropertyWrappers(
            wrapper: String,
            framework: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) async throws -> [SymbolSearchResult] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Normalize wrapper name (add @ if not present)
            let normalizedWrapper = wrapper.hasPrefix("@") ? wrapper : "@\(wrapper)"
            let wrapperPattern = "%\(normalizedWrapper)%"

            var conditions = ["s.attributes LIKE ?"]
            var params: [String] = [wrapperPattern]

            if let framework, !framework.isEmpty {
                conditions.append("m.framework = ?")
                params.append(framework.lowercased())
            }

            let whereClause = "WHERE " + conditions.joined(separator: " AND ")

            let sql = """
            SELECT DISTINCT
                s.doc_uri,
                f.title,
                COALESCE(m.framework, '') as framework,
                s.name,
                s.kind,
                s.signature,
                s.attributes,
                s.conformances,
                s.is_async,
                s.is_public
            FROM doc_symbols s
            JOIN docs_fts f ON s.doc_uri = f.uri
            LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
            \(whereClause)
            ORDER BY s.name
            LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Property wrapper search failed: \(errorMessage)")
            }

            var paramIndex: Int32 = 1
            for param in params {
                sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [SymbolSearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                let isAsync = sqlite3_column_int(statement, 8) != 0
                let isPublic = sqlite3_column_int(statement, 9) != 0

                results.append(SymbolSearchResult(
                    docUri: docUri,
                    docTitle: docTitle,
                    framework: framework,
                    symbolName: symbolName,
                    symbolKind: symbolKind,
                    signature: signature,
                    attributes: attributes,
                    conformances: conformances,
                    isAsync: isAsync,
                    isPublic: isPublic
                ))
            }

            return results
        }

        /// Search for concurrency patterns (async, actor, sendable, mainactor)
        /// - Parameters:
        ///   - pattern: Concurrency pattern to search for
        ///   - framework: Filter by framework
        ///   - limit: Maximum results
        /// - Returns: Array of matching symbol results
        public func searchConcurrencyPatterns(
            pattern: String,
            framework: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) async throws -> [SymbolSearchResult] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            var conditions: [String] = []
            var params: [String] = []

            // Map pattern to appropriate query
            switch pattern.lowercased() {
            case "async":
                conditions.append("s.is_async = 1")
            case "actor":
                conditions.append("s.kind = 'actor'")
            case "sendable":
                conditions.append("s.conformances LIKE '%Sendable%'")
            case "mainactor":
                conditions.append("s.attributes LIKE '%@MainActor%'")
            case "task":
                conditions.append("(s.name LIKE '%Task%' OR s.signature LIKE '%Task%')")
            case "asyncsequence":
                conditions.append("s.conformances LIKE '%AsyncSequence%'")
            default:
                // Generic search in attributes and conformances
                conditions.append("(s.attributes LIKE ? OR s.conformances LIKE ? OR s.signature LIKE ?)")
                let likePattern = "%\(pattern)%"
                params.append(likePattern)
                params.append(likePattern)
                params.append(likePattern)
            }

            if let framework, !framework.isEmpty {
                conditions.append("m.framework = ?")
                params.append(framework.lowercased())
            }

            let whereClause = "WHERE " + conditions.joined(separator: " AND ")

            let sql = """
            SELECT DISTINCT
                s.doc_uri,
                f.title,
                COALESCE(m.framework, '') as framework,
                s.name,
                s.kind,
                s.signature,
                s.attributes,
                s.conformances,
                s.is_async,
                s.is_public
            FROM doc_symbols s
            JOIN docs_fts f ON s.doc_uri = f.uri
            LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
            \(whereClause)
            ORDER BY s.name
            LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Concurrency pattern search failed: \(errorMessage)")
            }

            var paramIndex: Int32 = 1
            for param in params {
                sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [SymbolSearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                let isAsync = sqlite3_column_int(statement, 8) != 0
                let isPublic = sqlite3_column_int(statement, 9) != 0

                results.append(SymbolSearchResult(
                    docUri: docUri,
                    docTitle: docTitle,
                    framework: framework,
                    symbolName: symbolName,
                    symbolKind: symbolKind,
                    signature: signature,
                    attributes: attributes,
                    conformances: conformances,
                    isAsync: isAsync,
                    isPublic: isPublic
                ))
            }

            return results
        }

        /// Search for types by protocol conformance
        /// - Parameters:
        ///   - protocolName: Protocol name to search for
        ///   - framework: Filter by framework
        ///   - limit: Maximum results
        /// - Returns: Array of symbol results conforming to the protocol
        public func searchConformances(
            protocolName: String,
            framework: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) async throws -> [SymbolSearchResult] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let conformancePattern = "%\(protocolName)%"

            var conditions = ["s.conformances LIKE ?"]
            var params: [String] = [conformancePattern]

            if let framework, !framework.isEmpty {
                conditions.append("m.framework = ?")
                params.append(framework.lowercased())
            }

            let whereClause = "WHERE " + conditions.joined(separator: " AND ")

            let sql = """
            SELECT DISTINCT
                s.doc_uri,
                f.title,
                COALESCE(m.framework, '') as framework,
                s.name,
                s.kind,
                s.signature,
                s.attributes,
                s.conformances,
                s.is_async,
                s.is_public
            FROM doc_symbols s
            JOIN docs_fts f ON s.doc_uri = f.uri
            LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
            \(whereClause)
            ORDER BY s.name
            LIMIT ?;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Conformance search failed: \(errorMessage)")
            }

            var paramIndex: Int32 = 1
            for param in params {
                sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [SymbolSearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                let isAsync = sqlite3_column_int(statement, 8) != 0
                let isPublic = sqlite3_column_int(statement, 9) != 0

                results.append(SymbolSearchResult(
                    docUri: docUri,
                    docTitle: docTitle,
                    framework: framework,
                    symbolName: symbolName,
                    symbolKind: symbolKind,
                    signature: signature,
                    attributes: attributes,
                    conformances: conformances,
                    isAsync: isAsync,
                    isPublic: isPublic
                ))
            }

            return results
        }

        /// Get total symbol count in database
        public func symbolCount() async throws -> Int {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM doc_symbols;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return 0
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// List all frameworks with document counts
        public func listFrameworks() async throws -> [String: Int] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            SELECT framework, COUNT(*) as count
            FROM docs_metadata
            GROUP BY framework
            ORDER BY framework;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("List frameworks failed: \(errorMessage)")
            }

            var frameworks: [String: Int] = [:]

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let frameworkPtr = sqlite3_column_text(statement, 0) else {
                    continue
                }

                let framework = String(cString: frameworkPtr)
                let count = Int(sqlite3_column_int(statement, 1))
                frameworks[framework] = count
            }

            return frameworks
        }

        // MARK: - Framework Aliases

        /// Framework info with all three name forms
        public struct FrameworkInfo: Sendable {
            public let identifier: String // appintents
            public let importName: String // AppIntents
            public let displayName: String // App Intents
            public let docCount: Int
        }

        /// Register a framework alias (called during indexing when module is available)
        /// - Parameters:
        ///   - identifier: lowercase identifier from folder/URL (e.g., "appintents")
        ///   - displayName: display name from JSON module field (e.g., "App Intents")
        public func registerFrameworkAlias(identifier: String, displayName: String) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Derive import name by removing spaces from display name
            let importName = displayName.replacingOccurrences(of: " ", with: "")

            let sql = """
            INSERT INTO framework_aliases (identifier, import_name, display_name)
            VALUES (?, ?, ?)
            ON CONFLICT(identifier) DO UPDATE SET
                import_name = excluded.import_name,
                display_name = excluded.display_name;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return // Silently fail - alias registration is not critical
            }

            sqlite3_bind_text(statement, 1, (identifier as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (importName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (displayName as NSString).utf8String, -1, nil)

            _ = sqlite3_step(statement)
        }

        /// Resolve any framework input (identifier, import name, or display name) to identifier
        /// - Parameter input: Any of the three forms (e.g., "appintents", "AppIntents", "App Intents")
        /// - Returns: The identifier form (e.g., "appintents"), or nil if not found
        public func resolveFrameworkIdentifier(_ input: String) async throws -> String? {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // First try: exact match on identifier (most common case)
            let normalizedInput = input.lowercased().replacingOccurrences(of: " ", with: "")

            // Check if identifier exists directly
            let checkSql = "SELECT identifier FROM framework_aliases WHERE identifier = ? LIMIT 1;"
            var checkStmt: OpaquePointer?
            defer { sqlite3_finalize(checkStmt) }

            if sqlite3_prepare_v2(database, checkSql, -1, &checkStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStmt, 1, (normalizedInput as NSString).utf8String, -1, nil)
                if sqlite3_step(checkStmt) == SQLITE_ROW,
                   let ptr = sqlite3_column_text(checkStmt, 0) {
                    return String(cString: ptr)
                }
            }

            // Second try: match on import_name or display_name
            let sql = """
            SELECT identifier FROM framework_aliases
            WHERE import_name = ? OR display_name = ? OR LOWER(display_name) = ?
            LIMIT 1;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }

            sqlite3_bind_text(statement, 1, (input as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (input as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (input.lowercased() as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW,
               let ptr = sqlite3_column_text(statement, 0) {
                return String(cString: ptr)
            }

            // Fallback: return normalized input (might be a valid framework not in alias table yet)
            return normalizedInput
        }

        /// List all frameworks with full alias info and document counts
        public func listFrameworksWithAliases() async throws -> [FrameworkInfo] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            SELECT
                m.framework,
                COALESCE(a.import_name, m.framework) as import_name,
                COALESCE(a.display_name, m.framework) as display_name,
                COUNT(*) as count
            FROM docs_metadata m
            LEFT JOIN framework_aliases a ON m.framework = a.identifier
            GROUP BY m.framework
            ORDER BY m.framework;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("List frameworks with aliases failed: \(errorMessage)")
            }

            var frameworks: [FrameworkInfo] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let identifierPtr = sqlite3_column_text(statement, 0),
                      let importNamePtr = sqlite3_column_text(statement, 1),
                      let displayNamePtr = sqlite3_column_text(statement, 2)
                else {
                    continue
                }

                let info = FrameworkInfo(
                    identifier: String(cString: identifierPtr),
                    importName: String(cString: importNamePtr),
                    displayName: String(cString: displayNamePtr),
                    docCount: Int(sqlite3_column_int(statement, 3))
                )
                frameworks.append(info)
            }

            return frameworks
        }

        /// Get total document count
        public func documentCount() async throws -> Int {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM docs_metadata;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Count failed")
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// Get total sample code count
        public func sampleCodeCount() async throws -> Int {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM sample_code_metadata;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Sample code count failed")
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// Get total package count
        public func packageCount() async throws -> Int {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = "SELECT COUNT(*) FROM packages;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SearchError.searchFailed("Package count failed")
            }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return Int(sqlite3_column_int(statement, 0))
        }

        /// Search Swift packages
        public func searchPackages(
            query: String,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) async throws -> [Search.PackageResult] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw SearchError.invalidQuery("Query cannot be empty")
            }

            let sql = """
            SELECT
                p.id,
                p.name,
                p.owner,
                p.repository_url,
                p.documentation_url,
                p.stars,
                p.is_apple_official,
                p.description
            FROM packages p
            WHERE p.name LIKE ? OR p.description LIKE ? OR p.owner LIKE ?
            ORDER BY p.stars DESC
            LIMIT ?
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Package search failed: \(errorMessage)")
            }

            // Replace spaces with % wildcards for flexible matching (e.g., "swift argument parser" -> "swift%argument%parser")
            let flexibleQuery = query.split(separator: " ").joined(separator: "%")
            let searchPattern = "%\(flexibleQuery)%"
            sqlite3_bind_text(statement, 1, (searchPattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (searchPattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (searchPattern as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 4, Int32(limit))

            var results: [Search.PackageResult] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int64(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let owner = String(cString: sqlite3_column_text(statement, 2))
                let repositoryURL = String(cString: sqlite3_column_text(statement, 3))

                let documentationURL: String? = if sqlite3_column_type(statement, 4) != SQLITE_NULL {
                    String(cString: sqlite3_column_text(statement, 4))
                } else {
                    nil
                }

                let stars = Int(sqlite3_column_int(statement, 5))
                let isAppleOfficial = sqlite3_column_int(statement, 6) != 0

                let description: String? = if sqlite3_column_type(statement, 7) != SQLITE_NULL {
                    String(cString: sqlite3_column_text(statement, 7))
                } else {
                    nil
                }

                results.append(Search.PackageResult(
                    id: id,
                    name: name,
                    owner: owner,
                    repositoryURL: repositoryURL,
                    documentationURL: documentationURL,
                    stars: stars,
                    isAppleOfficial: isAppleOfficial,
                    description: description
                ))
            }

            return results
        }

        /// Output format for document content
        public enum DocumentFormat: Sendable {
            case json // Return full structured JSON
            case markdown // Return rendered markdown from rawMarkdown
        }

        /// Get document content by URI from database
        /// - Parameters:
        ///   - uri: The document URI
        ///   - format: Output format (.json or .markdown, default .json)
        ///     - `.json`: Returns full structured JSON with all fields (title, kind, declaration,
        ///       abstract, overview, sections, codeExamples, platforms, module, conformsTo, rawMarkdown)
        ///     - `.markdown`: Returns the rawMarkdown field for human-readable display
        /// - Returns: Document content in requested format, or nil if not found
        public func getDocumentContent(uri: String, format: DocumentFormat = .json) async throws -> String? {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Get json_data from metadata table
            let sql = """
            SELECT json_data
            FROM docs_metadata
            WHERE uri = ?
            LIMIT 1;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Get content failed: \(errorMessage)")
            }

            sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                // Not found in metadata, try FTS content as fallback
                return try await getContentFromFTS(uri: uri, format: format)
            }

            guard let jsonPtr = sqlite3_column_text(statement, 0) else {
                return try await getContentFromFTS(uri: uri, format: format)
            }

            let jsonString = String(cString: jsonPtr)

            switch format {
            case .json:
                // Return full structured JSON
                return jsonString

            case .markdown:
                // Try multiple fallbacks for markdown content
                let jsonData = Data(jsonString.utf8)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                if let page = try? decoder.decode(StructuredDocumentationPage.self, from: jsonData) {
                    // 1. Try rawMarkdown first
                    if let rawMarkdown = page.rawMarkdown, !rawMarkdown.isEmpty {
                        return rawMarkdown
                    }
                    // 2. Try generated markdown from structured data
                    let generated = page.markdown
                    if !generated.isEmpty, generated != "# \(page.title)\n\n" {
                        return generated
                    }
                }

                // 3. Fall back to FTS content table
                return try await getContentFromFTS(uri: uri, format: format)
            }
        }

        /// Get content from the FTS table as a fallback
        private func getContentFromFTS(uri: String, format: DocumentFormat) async throws -> String? {
            guard let database else {
                return nil
            }

            let ftsSql = """
            SELECT content
            FROM docs_fts
            WHERE uri = ?
            LIMIT 1;
            """

            var ftsStatement: OpaquePointer?
            defer { sqlite3_finalize(ftsStatement) }

            guard sqlite3_prepare_v2(database, ftsSql, -1, &ftsStatement, nil) == SQLITE_OK else {
                return nil
            }

            sqlite3_bind_text(ftsStatement, 1, (uri as NSString).utf8String, -1, nil)

            guard sqlite3_step(ftsStatement) == SQLITE_ROW,
                  let contentPtr = sqlite3_column_text(ftsStatement, 0) else {
                return nil
            }

            let content = String(cString: contentPtr)

            switch format {
            case .json:
                // Wrap FTS content in a minimal JSON structure
                let escaped = content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\t", with: "\\t")
                return "{\"uri\":\"\(uri)\",\"rawMarkdown\":\"\(escaped)\"}"
            case .markdown:
                return content
            }
        }

        /// Clear all documents from the index
        public func clearIndex() async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            DELETE FROM docs_fts;
            DELETE FROM docs_metadata;
            """

            var errorPointer: UnsafeMutablePointer<CChar>?
            defer { sqlite3_free(errorPointer) }

            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
                throw SearchError.sqliteError("Failed to clear index: \(errorMessage)")
            }
        }

        // MARK: - Helper Methods

        /// Detect programming language from content using heuristics
        /// Returns "swift", "objc", or defaults to "swift"
        private func detectLanguage(from content: String) -> String {
            // Look for Objective-C indicators
            let objcPatterns = [
                "#import",
                "@interface",
                "@implementation",
                "@property",
                "@synthesize",
                "@selector",
                "NSObject",
                "- (void)",
                "- (id)",
                "+ (void)",
                "+ (id)",
                "[[",
                "]]",
            ]

            let lowercased = content.lowercased()

            // Check for Obj-C patterns
            for pattern in objcPatterns {
                if content.contains(pattern) || lowercased.contains(pattern.lowercased()) {
                    return "objc"
                }
            }

            // Default to Swift (most Apple docs are Swift)
            return "swift"
        }

        // MARK: - Availability Extraction

        /// Extracted availability data from JSON
        private struct ExtractedAvailability {
            var iOS: String?
            var macOS: String?
            var tvOS: String?
            var watchOS: String?
            var visionOS: String?
            var source: String? // 'api', 'parsed', 'inherited', 'derived'
        }

        /// Extract availability from JSON string
        private func extractAvailabilityFromJSON(_ jsonString: String) -> ExtractedAvailability {
            var result = ExtractedAvailability()

            let data = Data(jsonString.utf8)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let availabilityArray = json["availability"] as? [[String: Any]]
            else {
                return result
            }

            // If availability array is empty, no availability data
            guard !availabilityArray.isEmpty else {
                return result
            }

            // Determine source based on presence of availability
            result.source = "api" // Default - could be enhanced to detect 'inherited', 'derived'

            for platform in availabilityArray {
                guard let name = platform["name"] as? String,
                      let introducedAt = platform["introducedAt"] as? String,
                      platform["unavailable"] as? Bool != true
                else { continue }

                switch name.lowercased() {
                case "ios", "ipados":
                    if result.iOS == nil || isVersionGreater(introducedAt, than: result.iOS!) {
                        result.iOS = introducedAt
                    }
                case "macos":
                    result.macOS = introducedAt
                case "tvos":
                    result.tvOS = introducedAt
                case "watchos":
                    result.watchOS = introducedAt
                case "visionos":
                    result.visionOS = introducedAt
                default:
                    break
                }
            }

            return result
        }

        /// Compare version strings - returns true if lhs > rhs
        private func isVersionGreater(_ lhs: String, than rhs: String) -> Bool {
            let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
            let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }

            for idx in 0..<max(lhsComponents.count, rhsComponents.count) {
                let lhsValue = idx < lhsComponents.count ? lhsComponents[idx] : 0
                let rhsValue = idx < rhsComponents.count ? rhsComponents[idx] : 0

                if lhsValue > rhsValue { return true }
                if lhsValue < rhsValue { return false }
            }
            return false
        }

        /// Helper to bind optional text to SQLite statement
        private func bindOptionalText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
            if let value {
                sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, index)
            }
        }

        private func extractSummary(
            from content: String,
            maxLength: Int = Shared.Constants.ContentLimit.summaryMaxLength
        ) -> String {
            // Remove YAML front matter
            var cleaned = content

            // Find and remove front matter (--- ... ---)
            if let firstDash = content.range(of: "---")?.lowerBound {
                if let secondDash = content.range(
                    of: "---",
                    range: content.index(after: firstDash)..<content.endIndex
                )?.upperBound {
                    cleaned = String(content[secondDash...])
                }
            }

            // Remove markdown headers at the start
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            while cleaned.hasPrefix("#") {
                if let newlineIndex = cleaned.firstIndex(of: "\n") {
                    cleaned = String(cleaned[cleaned.index(after: newlineIndex)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    break
                }
            }

            // Remove repeated title lines at the start (used for BM25 boosting)
            // Filter empty lines first to handle "Title\n\nTitle\n\nTitle" pattern
            var lines = cleaned.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Remove consecutive duplicate lines at the start
            while lines.count > 1, lines[0] == lines[1] {
                lines.removeFirst()
            }

            cleaned = lines.joined(separator: "\n\n")

            // Take first maxLength chars
            let truncated = String(cleaned.prefix(maxLength))

            // Find last sentence boundary
            if let lastPeriod = truncated.lastIndex(of: "."),
               truncated.distance(from: truncated.startIndex, to: lastPeriod) > 100 {
                return String(truncated[...lastPeriod])
            }

            // Otherwise, find last space to avoid cutting words
            if truncated.count == maxLength,
               let lastSpace = truncated.lastIndex(of: " ") {
                return String(truncated[..<lastSpace]) + "..."
            }

            return truncated
        }
    }
}
