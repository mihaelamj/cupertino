import Foundation
import SearchModels
import SQLite3

extension Search.Indexer {
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

    /// Attach synonyms to a `framework_aliases` row, creating the row if it
    /// does not exist. Returns the number of rows actually written.
    ///
    /// #1132: the prior UPDATE-only form silently no-opped whenever
    /// `registerFrameworkAlias` had not already inserted the row, so the 22
    /// hand-curated aliases (corenfc, corebluetooth, ...) never attached on a
    /// corpus where the alias table held only a few source-level rows. The
    /// upsert creates the row using `identifier` as the import/display-name
    /// fallback (a later `registerFrameworkAlias` refines those) and only
    /// overwrites `synonyms` on conflict, so existing names are preserved.
    /// - Parameters:
    ///   - identifier: The framework identifier (e.g., "corenfc")
    ///   - synonyms: Comma-separated alternate names (e.g., "nfc")
    @discardableResult
    public func updateFrameworkSynonyms(identifier: String, synonyms: String) async throws -> Int {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = """
        INSERT INTO framework_aliases (identifier, import_name, display_name, synonyms)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(identifier) DO UPDATE SET synonyms = excluded.synonyms;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        sqlite3_bind_text(statement, 1, (identifier as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (identifier as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (identifier as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (synonyms as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            return 0
        }
        return 1
    }
}
