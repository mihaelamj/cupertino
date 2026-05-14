import Foundation
import SearchModels
import SharedConstants
import SharedModels
import SQLite3

// swiftlint:disable function_body_length
// Justification: extracted from SearchIndex.swift; the original 4598-line
// file's class_body_length / function_body_length / function_parameter_count
// rationale carries forward to the per-concern slices.

extension Search.Index {
    /// Search Swift packages
    public func searchPackages(
        query: String,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) async throws -> [Search.PackageResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Search.Error.invalidQuery("Query cannot be empty")
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
            throw Search.Error.searchFailed("Package search failed: \(errorMessage)")
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

    // Output format for document content lives in SearchModels as
    // `Search.DocumentFormat` so resource-rendering consumers can pass
    // the value without taking a behavioural dep on Search.

    /// Get document content by URI from database
    /// - Parameters:
    ///   - uri: The document URI
    ///   - format: Output format (.json or .markdown, default .json)
    ///     - `.json`: Returns full structured JSON with all fields (title, kind, declaration,
    ///       abstract, overview, sections, codeExamples, platforms, module, conformsTo, rawMarkdown)
    ///     - `.markdown`: Returns the rawMarkdown field for human-readable display
    /// - Returns: Document content in requested format, or nil if not found
    public func getDocumentContent(uri: String, format: Search.DocumentFormat = .json) async throws -> String? {
        guard let database else {
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("Get content failed: \(errorMessage)")
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

            if let page = try? decoder.decode(Shared.Models.StructuredDocumentationPage.self, from: jsonData) {
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
    func getContentFromFTS(uri: String, format: Search.DocumentFormat) async throws -> String? {
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
            throw Search.Error.databaseNotInitialized
        }

        let sql = """
        DELETE FROM docs_fts;
        DELETE FROM docs_metadata;
        """

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            throw Search.Error.sqliteError("Failed to clear index: \(errorMessage)")
        }
    }

    // MARK: - Helper Methods

    // Detect programming language from content using heuristics
    // Returns "swift", "objc", or defaults to "swift"
}
