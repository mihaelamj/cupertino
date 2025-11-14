import Foundation
import SQLite3

// MARK: - Search Index

/// SQLite FTS5-based full-text search index for documentation
public actor SearchIndex {
    private var db: OpaquePointer?
    private let dbPath: URL
    private var isInitialized = false

    public init(
        dbPath: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".docsucker/search.db")
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
        self.isInitialized = true
    }

    // Note: deinit cannot access actor-isolated properties
    // SQLite connections will be closed when the process terminates
    // For explicit cleanup, call disconnect() before deallocation

    /// Close the database connection explicitly
    public func disconnect() {
        if let db {
            sqlite3_close(db)
            self.db = nil
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

        self.db = dbPointer
    }

    private func createTables() async throws {
        guard let db else {
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
            word_count INTEGER NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_framework ON docs_metadata(framework);
        """

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            throw SearchError.sqliteError("Failed to create tables: \(errorMessage)")
        }
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
        lastCrawled: Date
    ) async throws {
        guard let db else {
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

        guard sqlite3_prepare_v2(db, ftsSql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw SearchError.prepareFailed("FTS insert: \(errorMessage)")
        }

        sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (framework as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (summary as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw SearchError.insertFailed("FTS insert: \(errorMessage)")
        }

        // Insert metadata
        let metaSql = """
        INSERT OR REPLACE INTO docs_metadata
        (uri, framework, file_path, content_hash, last_crawled, word_count)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        var metaStatement: OpaquePointer?
        defer { sqlite3_finalize(metaStatement) }

        guard sqlite3_prepare_v2(db, metaSql, -1, &metaStatement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw SearchError.prepareFailed("Metadata insert: \(errorMessage)")
        }

        sqlite3_bind_text(metaStatement, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 2, (framework as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 3, (filePath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 4, (contentHash as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(metaStatement, 5, Int64(lastCrawled.timeIntervalSince1970))
        sqlite3_bind_int(metaStatement, 6, Int32(wordCount))

        guard sqlite3_step(metaStatement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw SearchError.insertFailed("Metadata insert: \(errorMessage)")
        }
    }

    // MARK: - Searching

    /// Search documents by query with optional framework filter
    public func search(
        query: String,
        framework: String? = nil,
        limit: Int = 20
    ) async throws -> [SearchResult] {
        guard let db else {
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

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
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
        var results: [SearchResult] = []

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
                SearchResult(
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
        guard let db else {
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

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
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
        guard let db else {
            throw SearchError.databaseNotInitialized
        }

        let sql = "SELECT COUNT(*) FROM docs_metadata;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchError.searchFailed("Count failed")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    /// Clear all documents from the index
    public func clearIndex() async throws {
        guard let db else {
            throw SearchError.databaseNotInitialized
        }

        let sql = """
        DELETE FROM docs_fts;
        DELETE FROM docs_metadata;
        """

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            throw SearchError.sqliteError("Failed to clear index: \(errorMessage)")
        }
    }

    // MARK: - Helper Methods

    private func extractSummary(from content: String, maxLength: Int = 500) -> String {
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
           truncated.distance(from: truncated.startIndex, to: lastPeriod) > 100
        {
            return String(truncated[...lastPeriod])
        }

        // Otherwise, find last space to avoid cutting words
        if truncated.count == maxLength,
           let lastSpace = truncated.lastIndex(of: " ")
        {
            return String(truncated[..<lastSpace]) + "..."
        }

        return truncated
    }
}
