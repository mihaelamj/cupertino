import Foundation
import Shared
import SQLite3

// MARK: - Search Index

// swiftlint:disable type_body_length function_body_length function_parameter_count
// Justification: This actor implements a complete SQLite FTS5 full-text search engine.
// It manages: database initialization, schema creation, document indexing with metadata,
// search query processing, statistics aggregation, and transaction management. The functions
// require multiple parameters to properly index documents with all metadata (id, title,
// framework, url, type, summary, content). Splitting would separate tightly-coupled SQL operations.
// File length: 421 lines | Type body length: 319 lines | Function body length: 66 lines | Parameters: 7
// Disabling: file_length (400 line limit), type_body_length (250 line limit),
//            function_body_length (50 line limit for SQL operations),
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
        public static let schemaVersion: Int32 = 4

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
            let sql = """
            CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
                uri,
                source,
                framework,
                title,
                content,
                summary,
                tokenize='porter unicode61'
            );

            CREATE TABLE IF NOT EXISTS docs_metadata (
                uri TEXT PRIMARY KEY,
                source TEXT NOT NULL DEFAULT 'apple-docs',
                framework TEXT NOT NULL,
                file_path TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                last_crawled INTEGER NOT NULL,
                word_count INTEGER NOT NULL,
                source_type TEXT DEFAULT 'apple',
                package_id INTEGER,
                json_data TEXT,
                FOREIGN KEY (package_id) REFERENCES packages(id)
            );

            CREATE INDEX IF NOT EXISTS idx_source ON docs_metadata(source);
            CREATE INDEX IF NOT EXISTS idx_framework ON docs_metadata(framework);
            CREATE INDEX IF NOT EXISTS idx_source_type ON docs_metadata(source_type);

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
                FOREIGN KEY (uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_docs_kind ON docs_structured(kind);
            CREATE INDEX IF NOT EXISTS idx_docs_module ON docs_structured(module);

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
                last_indexed INTEGER
            );

            CREATE INDEX IF NOT EXISTS idx_sample_framework ON sample_code_metadata(framework);

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

        /// Index a sample code entry
        public func indexSampleCode(
            url: String,
            framework: String,
            title: String,
            description: String,
            zipFilename: String,
            webURL: String
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

            // Insert metadata
            let metaSql = """
            INSERT OR REPLACE INTO sample_code_metadata
            (url, framework, zip_filename, web_url, last_indexed)
            VALUES (?, ?, ?, ?, ?);
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

            guard sqlite3_step(metaStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Sample code metadata insert: \(errorMessage)")
            }
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
            title: String,
            content: String,
            filePath: String,
            contentHash: String,
            lastCrawled: Date,
            sourceType: String = "apple",
            packageId: Int? = nil,
            jsonData: String? = nil
        ) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Extract summary (first 500 chars, stop at sentence)
            let summary = extractSummary(from: content)
            let wordCount = content.split(separator: " ").count

            // For non-apple-docs sources, framework can be nil or empty
            let effectiveFramework = framework ?? ""

            // Insert into FTS5 table
            let ftsSql = """
            INSERT OR REPLACE INTO docs_fts (uri, source, framework, title, content, summary)
            VALUES (?, ?, ?, ?, ?, ?);
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
            sqlite3_bind_text(statement, 4, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (summary as NSString).utf8String, -1, nil)

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

            // Insert metadata with JSON data
            // swiftlint:disable:next line_length
            let metaSql = "INSERT OR REPLACE INTO docs_metadata (uri, source, framework, file_path, content_hash, last_crawled, word_count, source_type, package_id, json_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"

            var metaStatement: OpaquePointer?
            defer { sqlite3_finalize(metaStatement) }

            guard sqlite3_prepare_v2(database, metaSql, -1, &metaStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Metadata insert: \(errorMessage)")
            }

            sqlite3_bind_text(metaStatement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 2, (source as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 3, (effectiveFramework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 4, (filePath as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 5, (contentHash as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(metaStatement, 6, Int64(lastCrawled.timeIntervalSince1970))
            sqlite3_bind_int(metaStatement, 7, Int32(wordCount))
            sqlite3_bind_text(metaStatement, 8, (sourceType as NSString).utf8String, -1, nil)

            if let packageId {
                sqlite3_bind_int(metaStatement, 9, Int32(packageId))
            } else {
                sqlite3_bind_null(metaStatement, 9)
            }

            sqlite3_bind_text(metaStatement, 10, (finalJsonData as NSString).utf8String, -1, nil)

            guard sqlite3_step(metaStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Metadata insert: \(errorMessage)")
            }
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
            jsonData: String
        ) async throws {
            // First, index the basic document (FTS + metadata with json_data)
            let content = page.rawMarkdown ?? page.markdown
            let summary = extractSummary(from: content)
            let wordCount = content.split(separator: " ").count

            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Insert into FTS5 table
            let ftsSql = """
            INSERT OR REPLACE INTO docs_fts (uri, source, framework, title, content, summary)
            VALUES (?, ?, ?, ?, ?, ?);
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
            sqlite3_bind_text(statement, 4, (page.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 6, (summary as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("FTS insert: \(errorMessage)")
            }

            // Insert metadata with json_data
            let metaSql = """
            INSERT OR REPLACE INTO docs_metadata
            (uri, source, framework, file_path, content_hash, last_crawled, word_count, source_type, json_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            sqlite3_bind_text(metaStatement, 4, (page.url.absoluteString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 5, (page.contentHash as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(metaStatement, 6, Int64(page.crawledAt.timeIntervalSince1970))
            sqlite3_bind_int(metaStatement, 7, Int32(wordCount))
            sqlite3_bind_text(metaStatement, 8, (page.source.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 9, (jsonData as NSString).utf8String, -1, nil)

            guard sqlite3_step(metaStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Metadata insert: \(errorMessage)")
            }

            // Insert structured fields for querying
            // swiftlint:disable:next line_length
            let structSql = "INSERT OR REPLACE INTO docs_structured (uri, url, title, kind, abstract, declaration, overview, module, platforms, conforms_to, inherited_by, conforming_types) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"

            var structStatement: OpaquePointer?
            defer { sqlite3_finalize(structStatement) }

            guard sqlite3_prepare_v2(database, structSql, -1, &structStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Structured insert: \(errorMessage)")
            }

            sqlite3_bind_text(structStatement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(structStatement, 2, (page.url.absoluteString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(structStatement, 3, (page.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(structStatement, 4, (page.kind.rawValue as NSString).utf8String, -1, nil)

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

            guard sqlite3_step(structStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Structured insert: \(errorMessage)")
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
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "apple-docs"

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
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "apple-docs"

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
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "apple-docs"

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
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "apple-docs"

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
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "apple-docs"

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
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "apple-docs"

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
                let source = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "apple-docs"

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
        /// - apple-docs: Apple Developer documentation
        /// - swift-book: Swift Book documentation from docs.swift.org
        /// - swift-org: Swift.org documentation
        /// - swift-evolution: Swift Evolution proposals
        /// - packages: Swift Package documentation
        /// - apple-sample-code: Apple sample code projects
        private static let knownSourcePrefixes = [
            "apple-docs",
            "swift-book",
            "swift-org",
            "swift-evolution",
            "packages",
            "apple-sample-code",
        ]

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

        /// Search documents by query with optional source and framework filters
        /// If query starts with a known source prefix (e.g., "swift-book"), it's extracted as a filter
        /// - Parameters:
        ///   - query: Search query (may include source prefix like "swift-evolution actors")
        ///   - source: Optional source filter (apple-docs, swift-evolution, etc.)
        ///   - framework: Optional framework filter (swiftui, foundation, etc. - only for apple-docs)
        ///   - limit: Maximum number of results
        public func search(
            query: String,
            source: String? = nil,
            framework: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw SearchError.invalidQuery("Query cannot be empty")
            }

            // Extract source prefix from query if no explicit source provided
            let (detectedSource, remainingQuery) = source == nil
                ? extractSourcePrefix(query)
                : (nil, query)

            // Use explicit source or detected source
            let effectiveSource = source ?? detectedSource

            // Use remaining query after extracting source prefix
            let queryToSearch = remainingQuery.isEmpty ? query : remainingQuery
            let sanitizedQuery = sanitizeFTS5Query(queryToSearch)

            var sql = """
            SELECT
                f.uri,
                f.source,
                f.framework,
                f.title,
                f.summary,
                m.file_path,
                m.word_count,
                bm25(docs_fts) as rank
            FROM docs_fts f
            JOIN docs_metadata m ON f.uri = m.uri
            WHERE docs_fts MATCH ?
            """

            if effectiveSource != nil {
                sql += " AND f.source = ?"
            }
            if framework != nil {
                sql += " AND f.framework = ?"
            }

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
            if let framework {
                sqlite3_bind_text(statement, paramIndex, (framework as NSString).utf8String, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            // Execute and collect results
            // Column order: uri(0), source(1), framework(2), title(3), summary(4), file_path(5), word_count(6), rank(7)
            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let uriPtr = sqlite3_column_text(statement, 0),
                      let sourcePtr = sqlite3_column_text(statement, 1),
                      let frameworkPtr = sqlite3_column_text(statement, 2),
                      let titlePtr = sqlite3_column_text(statement, 3),
                      let summaryPtr = sqlite3_column_text(statement, 4),
                      let filePathPtr = sqlite3_column_text(statement, 5)
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
                let rank = sqlite3_column_double(statement, 7)

                results.append(
                    Search.Result(
                        uri: uri,
                        source: source,
                        framework: framework,
                        title: title,
                        summary: summary,
                        filePath: filePath,
                        wordCount: wordCount,
                        rank: rank
                    )
                )
            }

            return results
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
