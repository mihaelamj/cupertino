import ASTIndexer
import Foundation
import Shared
import SQLite3

// swiftlint:disable type_body_length function_body_length function_parameter_count
// Justification: extracted from SearchIndex.swift; the original 4598-line
// file's class_body_length / function_body_length / function_parameter_count
// rationale carries forward to the per-concern slices.

extension Search.Index {
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

    /// Extract AST symbols and imports from stored code examples and fold them
    /// into the existing symbol/import tables + the denormalised `symbols` blob
    /// on `docs_metadata` (#192 section D).
    ///
    /// Only Swift blocks are parsed. Non-Swift blocks are ignored — the
    /// extractor relies on SwiftSyntax and would just produce empty results.
    ///
    /// Call this AFTER `indexCodeExamples(docUri:codeExamples:)` so the
    /// referenced blocks are already durable. `docs_metadata.symbols` is
    /// only written when there is at least one unique symbol name.
    public func extractCodeExampleSymbols(
        docUri: String,
        codeExamples: [(code: String, language: String)]
    ) async throws {
        guard database != nil else {
            throw SearchError.databaseNotInitialized
        }

        let extractor = ASTIndexer.SwiftSourceExtractor()
        var collectedSymbols: [ASTIndexer.ExtractedSymbol] = []
        var collectedImports: [ASTIndexer.ExtractedImport] = []

        for example in codeExamples where Self.isSwiftLanguage(example.language) {
            let result = extractor.extract(from: example.code)
            collectedSymbols.append(contentsOf: result.symbols)
            collectedImports.append(contentsOf: result.imports)
        }

        // Append (do NOT clear) so declaration-derived symbols inserted by
        // `indexStructuredDocument` survive. The structured-doc indexer
        // owns the clear; this method only adds code-example findings on
        // top.
        if !collectedSymbols.isEmpty {
            try await indexDocSymbols(docUri: docUri, symbols: collectedSymbols)
        }
        if !collectedImports.isEmpty {
            try await indexDocImports(docUri: docUri, imports: collectedImports)
        }
        try await recomputeSymbolsBlob(docUri: docUri)
    }

    func clearDocSymbols(docUri: String) async throws {
        guard let database else { return }
        let sql = "DELETE FROM doc_symbols WHERE doc_uri = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, (docUri as NSString).utf8String, -1, nil)
        _ = sqlite3_step(stmt)
    }

    func clearDocImports(docUri: String) async throws {
        guard let database else { return }
        let sql = "DELETE FROM doc_imports WHERE doc_uri = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, (docUri as NSString).utf8String, -1, nil)
        _ = sqlite3_step(stmt)
    }

    /// Update the denormalised `symbols` column on `docs_metadata` with a
    /// tab-separated, sorted list of unique symbol names. Silent no-op if
    /// the `docs_metadata` row does not yet exist for `docUri`.
    /// Recompute the denormalised `docs_metadata.symbols` and the
    /// `docs_fts.symbols` columns from whatever is currently in
    /// `doc_symbols` for `docUri`. Idempotent — produces the same output
    /// regardless of how many `indexDocSymbols` calls landed first, and
    /// regardless of duplicate rows in `doc_symbols`.
    ///
    /// Single source of truth: `doc_symbols.name`. Declaration-derived
    /// names and code-example-derived names both flow into the same
    /// table, so this method picks them up uniformly.
    func recomputeSymbolsBlob(docUri: String) async throws {
        guard let database else {
            throw SearchError.databaseNotInitialized
        }

        // Read all symbol names for this doc, dedupe, sort.
        var names: Set<String> = []
        do {
            let sql = "SELECT name FROM doc_symbols WHERE doc_uri = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
                return
            }
            sqlite3_bind_text(stmt, 1, (docUri as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    names.insert(String(cString: ptr))
                }
            }
        }

        // Update denormalised column on docs_metadata (tab-separated,
        // human-readable for SQL consumers).
        let metaSql = "UPDATE docs_metadata SET symbols = ? WHERE uri = ?;"
        var metaStmt: OpaquePointer?
        defer { sqlite3_finalize(metaStmt) }
        if sqlite3_prepare_v2(database, metaSql, -1, &metaStmt, nil) == SQLITE_OK {
            if names.isEmpty {
                sqlite3_bind_null(metaStmt, 1)
            } else {
                let blob = names.sorted().joined(separator: "\t")
                sqlite3_bind_text(metaStmt, 1, (blob as NSString).utf8String, -1, nil)
            }
            sqlite3_bind_text(metaStmt, 2, (docUri as NSString).utf8String, -1, nil)
            _ = sqlite3_step(metaStmt)
        }

        // Update FTS index column with a space-separated form so each
        // name becomes its own token under unicode61 + porter.
        let ftsSql = "UPDATE docs_fts SET symbols = ? WHERE uri = ?;"
        var ftsStmt: OpaquePointer?
        defer { sqlite3_finalize(ftsStmt) }
        if sqlite3_prepare_v2(database, ftsSql, -1, &ftsStmt, nil) == SQLITE_OK {
            let ftsBlob = names.isEmpty ? "" : names.sorted().joined(separator: " ")
            sqlite3_bind_text(ftsStmt, 1, (ftsBlob as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStmt, 2, (docUri as NSString).utf8String, -1, nil)
            _ = sqlite3_step(ftsStmt)
        }
    }

    /// Classify a code-block language tag as Swift. Accepts the variants
    /// Apple docs and the Swift book actually ship.
    static func isSwiftLanguage(_ language: String) -> Bool {
        switch language.lowercased() {
        case "swift", "swift-symbols", "swiftsymbols":
            return true
        default:
            return false
        }
    }

    // Search code examples
}
