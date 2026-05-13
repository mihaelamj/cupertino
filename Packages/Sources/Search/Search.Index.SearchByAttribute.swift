import Foundation
import SharedConstants
import SharedCore
import SQLite3

extension Search.Index {
    /// Get full JSON data for a document
    public func getDocumentJSON(uri: String) async throws -> String? {
        guard let database else {
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("Kind search prepare failed")
        }

        sqlite3_bind_text(statement, 1, (kind as NSString).utf8String, -1, nil)

        var paramIndex: Int32 = 2
        if let framework {
            sqlite3_bind_text(statement, paramIndex, (framework.lowercased() as NSString).utf8String, -1, nil)
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
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("Conforms search prepare failed")
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
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("Module search prepare failed")
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
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("Inherited search prepare failed")
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
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("Conforming types search prepare failed")
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
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("Declaration search prepare failed")
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
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("Platform search prepare failed")
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
    static let knownSourcePrefixes = Shared.Constants.SourcePrefix.allPrefixes

    // Extract source prefix from query if present.
    // - Returns: (detectedSource, remainingQuery)
    // - Example: "swift-evolution actors" -> ("swift-evolution", "actors")
}
