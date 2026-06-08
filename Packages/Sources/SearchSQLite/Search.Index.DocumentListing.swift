import Foundation
import SearchModels
import SharedConstants
import SQLite3

// MARK: - Search.DocumentListing

extension Search.Index: Search.DocumentListing {
    public func listDocuments(
        source: String,
        framework: String,
        offset: Int,
        limit: Int
    ) async throws -> Search.DocumentListPage {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let query = try await makeDocumentListQuery(
            source: source,
            framework: framework,
            offset: offset,
            limit: limit
        )
        let total = try countDocuments(
            database: database,
            source: query.source,
            framework: query.framework
        )
        let documents = query.limit > 0
            ? try loadDocumentListItems(database: database, query: query)
            : []

        return Search.DocumentListPage(
            source: query.source,
            framework: query.framework,
            offset: query.offset,
            limit: query.limit,
            total: total,
            documents: documents
        )
    }

    private func makeDocumentListQuery(
        source: String,
        framework: String,
        offset: Int,
        limit: Int
    ) async throws -> DocumentListQuery {
        let effectiveSource = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Shared.Constants.SourcePrefix.appleDocs
            : source.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedFramework = framework.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedFramework.isEmpty else {
            throw Search.Error.invalidQuery("Framework is required")
        }

        let resolvedFramework = try await resolveFrameworkIdentifier(requestedFramework)
            ?? requestedFramework.lowercased().replacingOccurrences(of: " ", with: "")
        let safeOffset = max(offset, 0)
        let safeLimit = min(max(limit, 0), Shared.Constants.Limit.maxDocumentListLimit)

        return DocumentListQuery(
            source: effectiveSource,
            framework: resolvedFramework,
            offset: safeOffset,
            limit: safeLimit
        )
    }

    private func loadDocumentListItems(
        database: OpaquePointer,
        query: DocumentListQuery
    ) throws -> [Search.DocumentListItem] {
        let sql = """
        SELECT
            m.uri,
            COALESCE(NULLIF(s.title, ''), NULLIF(json_extract(m.json_data, '$.title'), ''), m.uri) AS title,
            COALESCE(NULLIF(s.kind, ''), NULLIF(json_extract(m.json_data, '$.kind'), ''), NULLIF(m.kind, ''), 'unknown') AS kind
        FROM docs_metadata m
        LEFT JOIN docs_structured s ON s.uri = m.uri
        WHERE m.source = ? AND m.framework = ?
        ORDER BY LOWER(title), m.uri
        LIMIT ? OFFSET ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("List documents failed: \(errorMessage)")
        }

        sqlite3_bind_text(statement, 1, (query.source as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (query.framework as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 3, Int32(query.limit))
        sqlite3_bind_int64(statement, 4, sqlite3_int64(query.offset))

        var documents: [Search.DocumentListItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let uri = Self.textColumn(statement, 0) ?? ""
            guard !uri.isEmpty else { continue }
            documents.append(Search.DocumentListItem(
                uri: uri,
                title: Self.textColumn(statement, 1) ?? uri,
                kind: Self.textColumn(statement, 2) ?? "unknown"
            ))
        }

        return documents
    }

    private func countDocuments(
        database: OpaquePointer,
        source: String,
        framework: String
    ) throws -> Int {
        let sql = """
        SELECT COUNT(*)
        FROM docs_metadata
        WHERE source = ? AND framework = ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Count documents failed: \(errorMessage)")
        }

        sqlite3_bind_text(statement, 1, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (framework as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        return String(cString: pointer)
    }
}

private struct DocumentListQuery {
    let source: String
    let framework: String
    let offset: Int
    let limit: Int
}
