import Foundation
import SearchModels
import SharedConstants
import SQLite3

// swiftlint:disable function_body_length
// Justification: extracted from SearchIndex.swift; the original 4598-line
// file's class_body_length / function_body_length / function_parameter_count
// rationale carries forward to the per-concern slices.

/// #177 — shared signal-rank ORDER BY clause for the 4 AST semantic search
/// queries (`searchSymbols`, `searchPropertyWrappers`,
/// `searchConcurrencyPatterns`, `searchConformances`). Pre-fix every
/// query did a flat `ORDER BY s.name`, which surfaced `==(_:_:)` operator
/// overloads + synthesised `Equatable` / `Hashable` / `Comparable`
/// conformance members ahead of canonical type pages. A developer
/// searching for `mainactor` got `==` operators from RealityKit before
/// any real view-model class; `task` got `==` / `<=` / `<` on
/// `Task<Success, Failure>` and `TaskPriority` before any real Task
/// usage; etc.
///
/// Two-tier reranking deprioritises (does NOT exclude — that would
/// break "show me everything" workflows) the boilerplate:
///
/// Tier 1: rows whose symbol name is one of the auto-synthesised /
///   operator-overload names go LAST among everything else.
/// Tier 2: within tier 1, canonical type kinds (class / struct / enum /
///   protocol / actor) come first; type-shape sub-kinds (typealias /
///   macro) next; member-shape (method / function / property /
///   initializer) third; pages explicitly tagged `kind=operator`
///   fourth; everything else (including `kind=unknown`) in tier 5.
///
/// `s.name` ties remaining ordering — preserves the pre-fix alphabetic
/// shape for rows in the same kind+name-shape bucket.
private let signalRankOrderClause = """
ORDER BY
    CASE WHEN s.name IN (
        '==(_:_:)', '!=(_:_:)', '<(_:_:)', '<=(_:_:)', '>(_:_:)', '>=(_:_:)',
        '~=(_:_:)', 'hash(into:)',
        '==', '!=', '<', '<=', '>', '>='
    ) THEN 1 ELSE 0 END,
    CASE
        WHEN s.kind IN ('class', 'struct', 'enum', 'protocol', 'actor') THEN 0
        WHEN s.kind IN ('typealias', 'macro') THEN 1
        WHEN s.kind IN ('method', 'function', 'property', 'initializer', 'subscript', 'case') THEN 2
        WHEN s.kind = 'operator' THEN 3
        ELSE 4
    END,
    s.name
"""

extension Search.Index {
    public func searchSymbols(
        query: String?,
        kind: String? = nil,
        isAsync: Bool? = nil,
        framework: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
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
        \(signalRankOrderClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Symbol search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            if let str = param as? String {
                sqlite3_bind_text(statement, paramIndex, (str as NSString).utf8String, -1, nil)
            }
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
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

            results.append(Search.SymbolSearchResult(
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
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
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
        \(signalRankOrderClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Property wrapper search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
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

            results.append(Search.SymbolSearchResult(
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
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
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
        \(signalRankOrderClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Concurrency pattern search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
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

            results.append(Search.SymbolSearchResult(
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
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
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
        \(signalRankOrderClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Conformance search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
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

            results.append(Search.SymbolSearchResult(
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
