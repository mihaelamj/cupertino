import Foundation
import Shared
import SQLite3

// swiftlint:disable type_body_length function_body_length function_parameter_count file_length
// Justification: extracted from SearchIndex.swift; the original 4598-line
// file's class_body_length / function_body_length / function_parameter_count
// rationale carries forward to the per-concern slices.

extension Search.Index {
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

    // Get total symbol count in database
}
