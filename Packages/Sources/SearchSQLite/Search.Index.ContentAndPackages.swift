import Foundation
import SearchModels
import SharedConstants
import SQLite3

extension Search.Index {
    // #789: searchPackages removed along with the search.db `packages`
    // table. Package search lives in packages.db via `cupertino package-search`.

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
            // #607 (read-side fallback): when the stored wrapper carries
            // `rawMarkdown:null` (the 3 string-content strategies pre-#608
            // — SwiftEvolution / HIG / AppleArchive — plus every doc indexed
            // before that PR shipped), merge the full body from
            // `docs_fts.content` into the returned wrapper. `read_document`
            // (MCP tool) and `cupertino read` (default JSON) both read this
            // method's output, so without the merge an AI agent calling
            // `read_document` on a swift-evolution / hig / apple-archive
            // URI receives only the title wrapper. Pre-fix the `.markdown`
            // path already fell back to FTS for similar reasons; this
            // extends the same defence to the structured-JSON consumers.
            if let merged = try? await mergeFTSContentIfRawMarkdownMissing(
                uri: uri,
                jsonString: jsonString
            ) {
                return merged
            }
            // Unparseable wrapper / no FTS content / rawMarkdown already
            // populated: hand back the stored JSON verbatim.
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

    /// #607 read-side fallback. Inspect the stored `docs_metadata.json_data`
    /// wrapper for `uri`; if its `rawMarkdown` field is missing, JSON-null,
    /// or empty, pull the full body from `docs_fts.content` and inject it
    /// back into the wrapper before returning. Returns `nil` when the
    /// wrapper is unparseable, already carries non-empty `rawMarkdown`, or
    /// has no FTS row to fall back to — callers treat `nil` as "use the
    /// stored wrapper verbatim". Re-serialisation goes through
    /// `JSONSerialization` so the injected content's quotes, backslashes,
    /// newlines, backticks, and tabs come back out as valid JSON.
    func mergeFTSContentIfRawMarkdownMissing(
        uri: String,
        jsonString: String
    ) async throws -> String? {
        let data = Data(jsonString.utf8)
        guard var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Stored wrapper isn't valid JSON. Bail; the verbatim path is
            // the safer return.
            return nil
        }

        // `rawMarkdown` already populated → nothing to do. The check accepts
        // either a non-empty string (the post-#608 indexer path) or the
        // structured-page wrapper where `rawMarkdown` is one of several
        // populated body fields.
        if let raw = payload["rawMarkdown"] as? String, !raw.isEmpty {
            return nil
        }

        // rawMarkdown is null / missing / empty → try the FTS sidecar.
        guard let ftsContent = try await getContentFromFTS(uri: uri, format: .markdown),
              !ftsContent.isEmpty else {
            return nil
        }

        payload["rawMarkdown"] = ftsContent
        guard let merged = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        ),
            let mergedString = String(data: merged, encoding: .utf8) else {
            return nil
        }
        return mergedString
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

    // MARK: - Helper Methods

    /// Detect programming language from content using heuristics
    /// Returns "swift", "objc", or defaults to "swift"
    /// Look up availability for a framework from indexed docs
    public func getFrameworkAvailability(framework: String) async -> Search.FrameworkAvailability {
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

        return Search.FrameworkAvailability(
            minIOS: minIOS,
            minMacOS: minMacOS,
            minTvOS: minTvOS,
            minWatchOS: minWatchOS,
            minVisionOS: minVisionOS
        )
    }
}
