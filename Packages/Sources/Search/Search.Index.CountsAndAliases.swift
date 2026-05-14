import Foundation
import SearchModels
import SharedConstants
import SharedUtils
import SQLite3

extension Search.Index {
    public func symbolCount() async throws -> Int {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = Shared.Utils.SQL.countRows(in: "doc_symbols")

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    /// List all frameworks with document counts
    public func listFrameworks() async throws -> [String: Int] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
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
            throw Search.Error.searchFailed("List frameworks failed: \(errorMessage)")
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

    // MARK: - Framework Aliases

    /// Framework info with all three name forms
    public struct FrameworkInfo: Sendable {
        public let identifier: String // appintents
        public let importName: String // AppIntents
        public let displayName: String // App Intents
        public let docCount: Int
    }

    /// Register a framework alias (called during indexing when module is available)
    /// - Parameters:
    ///   - identifier: lowercase identifier from folder/URL (e.g., "appintents")
    ///   - displayName: display name from JSON module field (e.g., "App Intents")
    public func registerFrameworkAlias(identifier: String, displayName: String) async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Derive import name by removing spaces from display name
        let importName = displayName.replacingOccurrences(of: " ", with: "")

        let sql = """
        INSERT INTO framework_aliases (identifier, import_name, display_name)
        VALUES (?, ?, ?)
        ON CONFLICT(identifier) DO UPDATE SET
            import_name = excluded.import_name,
            display_name = excluded.display_name;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return // Silently fail - alias registration is not critical
        }

        sqlite3_bind_text(statement, 1, (identifier as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (importName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (displayName as NSString).utf8String, -1, nil)

        _ = sqlite3_step(statement)
    }

    /// Update synonyms for an existing framework alias
    /// - Parameters:
    ///   - identifier: The framework identifier (e.g., "corenfc")
    ///   - synonyms: Comma-separated alternate names (e.g., "nfc")
    public func updateFrameworkSynonyms(identifier: String, synonyms: String) async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = "UPDATE framework_aliases SET synonyms = ? WHERE identifier = ?;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        sqlite3_bind_text(statement, 1, (synonyms as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (identifier as NSString).utf8String, -1, nil)

        _ = sqlite3_step(statement)
    }

    /// Resolve any framework input (identifier, import name, or display name) to identifier
    /// - Parameter input: Any of the three forms (e.g., "appintents", "AppIntents", "App Intents")
    /// - Returns: The identifier form (e.g., "appintents"), or nil if not found
    public func resolveFrameworkIdentifier(_ input: String) async throws -> String? {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // First try: exact match on identifier (most common case)
        let normalizedInput = input.lowercased().replacingOccurrences(of: " ", with: "")

        // Check if identifier exists directly
        let checkSql = "SELECT identifier FROM framework_aliases WHERE identifier = ? LIMIT 1;"
        var checkStmt: OpaquePointer?
        defer { sqlite3_finalize(checkStmt) }

        if sqlite3_prepare_v2(database, checkSql, -1, &checkStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(checkStmt, 1, (normalizedInput as NSString).utf8String, -1, nil)
            if sqlite3_step(checkStmt) == SQLITE_ROW,
               let ptr = sqlite3_column_text(checkStmt, 0) {
                return String(cString: ptr)
            }
        }

        // Second try: match on import_name or display_name
        let sql = """
        SELECT identifier FROM framework_aliases
        WHERE import_name = ? OR display_name = ? OR LOWER(display_name) = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        sqlite3_bind_text(statement, 1, (input as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (input as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (input.lowercased() as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW,
           let ptr = sqlite3_column_text(statement, 0) {
            return String(cString: ptr)
        }

        // Third try: match on synonyms (comma-separated alternate names)
        let synonymSql = """
        SELECT identifier FROM framework_aliases
        WHERE synonyms IS NOT NULL
        AND (',' || LOWER(synonyms) || ',') LIKE '%,' || ? || ',%'
        LIMIT 1;
        """

        var synStmt: OpaquePointer?
        defer { sqlite3_finalize(synStmt) }

        if sqlite3_prepare_v2(database, synonymSql, -1, &synStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(synStmt, 1, (normalizedInput as NSString).utf8String, -1, nil)
            if sqlite3_step(synStmt) == SQLITE_ROW,
               let ptr = sqlite3_column_text(synStmt, 0) {
                return String(cString: ptr)
            }
        }

        // Fallback: return normalized input (might be a valid framework not in alias table yet)
        return normalizedInput
    }

    /// List all frameworks with full alias info and document counts
    public func listFrameworksWithAliases() async throws -> [FrameworkInfo] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = """
        SELECT
            m.framework,
            COALESCE(a.import_name, m.framework) as import_name,
            COALESCE(a.display_name, m.framework) as display_name,
            COUNT(*) as count
        FROM docs_metadata m
        LEFT JOIN framework_aliases a ON m.framework = a.identifier
        GROUP BY m.framework
        ORDER BY m.framework;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("List frameworks with aliases failed: \(errorMessage)")
        }

        var frameworks: [FrameworkInfo] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let identifierPtr = sqlite3_column_text(statement, 0),
                  let importNamePtr = sqlite3_column_text(statement, 1),
                  let displayNamePtr = sqlite3_column_text(statement, 2)
            else {
                continue
            }

            let info = FrameworkInfo(
                identifier: String(cString: identifierPtr),
                importName: String(cString: importNamePtr),
                displayName: String(cString: displayNamePtr),
                docCount: Int(sqlite3_column_int(statement, 3))
            )
            frameworks.append(info)
        }

        return frameworks
    }

    /// Get total document count
    public func documentCount() async throws -> Int {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = Shared.Utils.SQL.countRows(in: "docs_metadata")

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Search.Error.searchFailed("Count failed")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    /// Get total sample code count
    public func sampleCodeCount() async throws -> Int {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = Shared.Utils.SQL.countRows(in: "sample_code_metadata")

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Search.Error.searchFailed("Sample code count failed")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    /// Get total package count
    public func packageCount() async throws -> Int {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = Shared.Utils.SQL.countRows(in: "packages")

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Search.Error.searchFailed("Package count failed")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }
}
