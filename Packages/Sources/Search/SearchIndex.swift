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
            try await createTables()
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

        private func createTables() async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // FTS5 virtual table for full-text search
            let sql = """
            CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
                uri,
                framework,
                title,
                content,
                summary,
                tokenize='porter unicode61'
            );

            CREATE TABLE IF NOT EXISTS docs_metadata (
                uri TEXT PRIMARY KEY,
                framework TEXT NOT NULL,
                file_path TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                last_crawled INTEGER NOT NULL,
                word_count INTEGER NOT NULL,
                source_type TEXT DEFAULT 'apple',
                package_id INTEGER,
                FOREIGN KEY (package_id) REFERENCES packages(id)
            );

            CREATE INDEX IF NOT EXISTS idx_framework ON docs_metadata(framework);
            CREATE INDEX IF NOT EXISTS idx_source_type ON docs_metadata(source_type);

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
        public func indexDocument(
            uri: String,
            framework: String,
            title: String,
            content: String,
            filePath: String,
            contentHash: String,
            lastCrawled: Date,
            sourceType: String = "apple",
            packageId: Int? = nil
        ) async throws {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            // Extract summary (first 500 chars, stop at sentence)
            let summary = extractSummary(from: content)
            let wordCount = content.split(separator: " ").count

            // Insert into FTS5 table
            let ftsSql = """
            INSERT OR REPLACE INTO docs_fts (uri, framework, title, content, summary)
            VALUES (?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, ftsSql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("FTS insert: \(errorMessage)")
            }

            sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (framework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 5, (summary as NSString).utf8String, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("FTS insert: \(errorMessage)")
            }

            // Insert metadata
            let metaSql = """
            INSERT OR REPLACE INTO docs_metadata
            (uri, framework, file_path, content_hash, last_crawled, word_count, source_type, package_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """

            var metaStatement: OpaquePointer?
            defer { sqlite3_finalize(metaStatement) }

            guard sqlite3_prepare_v2(database, metaSql, -1, &metaStatement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.prepareFailed("Metadata insert: \(errorMessage)")
            }

            sqlite3_bind_text(metaStatement, 1, (uri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 2, (framework as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 3, (filePath as NSString).utf8String, -1, nil)
            sqlite3_bind_text(metaStatement, 4, (contentHash as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(metaStatement, 5, Int64(lastCrawled.timeIntervalSince1970))
            sqlite3_bind_int(metaStatement, 6, Int32(wordCount))
            sqlite3_bind_text(metaStatement, 7, (sourceType as NSString).utf8String, -1, nil)

            if let packageId {
                sqlite3_bind_int(metaStatement, 8, Int32(packageId))
            } else {
                sqlite3_bind_null(metaStatement, 8)
            }

            guard sqlite3_step(metaStatement) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.insertFailed("Metadata insert: \(errorMessage)")
            }
        }

        // MARK: - Searching

        /// Search documents by query with optional framework filter
        public func search(
            query: String,
            framework: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) async throws -> [Search.Result] {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw SearchError.invalidQuery("Query cannot be empty")
            }

            var sql = """
            SELECT
                f.uri,
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

            // Bind parameters
            sqlite3_bind_text(statement, 1, (query as NSString).utf8String, -1, nil)

            if let framework {
                sqlite3_bind_text(statement, 2, (framework as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 3, Int32(limit))
            } else {
                sqlite3_bind_int(statement, 2, Int32(limit))
            }

            // Execute and collect results
            var results: [Search.Result] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let uriPtr = sqlite3_column_text(statement, 0),
                      let frameworkPtr = sqlite3_column_text(statement, 1),
                      let titlePtr = sqlite3_column_text(statement, 2),
                      let summaryPtr = sqlite3_column_text(statement, 3),
                      let filePathPtr = sqlite3_column_text(statement, 4)
                else {
                    continue
                }

                let uri = String(cString: uriPtr)
                let framework = String(cString: frameworkPtr)
                let title = String(cString: titlePtr)
                let summary = String(cString: summaryPtr)
                let filePath = String(cString: filePathPtr)
                let wordCount = Int(sqlite3_column_int(statement, 5))
                let rank = sqlite3_column_double(statement, 6)

                results.append(
                    Search.Result(
                        uri: uri,
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

        /// Get document content by URI from database
        /// Returns nil if document not found in database
        public func getDocumentContent(uri: String) async throws -> String? {
            guard let database else {
                throw SearchError.databaseNotInitialized
            }

            let sql = """
            SELECT content
            FROM docs_fts
            WHERE uri = ?
            LIMIT 1;
            """

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                throw SearchError.searchFailed("Get content failed: \(errorMessage)")
            }

            // Bind URI parameter
            sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)

            // Execute query
            guard sqlite3_step(statement) == SQLITE_ROW else {
                // Document not found in database
                return nil
            }

            // Extract content
            guard let contentPtr = sqlite3_column_text(statement, 0) else {
                return nil
            }

            return String(cString: contentPtr)
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
