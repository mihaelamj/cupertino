import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #837 PR-2 — apple_imports_json SQL pattern pinning

/// PR-2 ships:
/// 1. `Search.PackageQuery.searchSymbolsForPackages` private helper +
///    boost in `answer(...)` reading `package_symbols.generic_constraints`.
/// 2. `appleImport: String?` parameter on `answer(...)` that adds an
///    `AND m.apple_imports_json LIKE '%"' || ? || '"%'` clause to the
///    candidate-fetch SQL.
/// 3. `--apple-imports <module>` CLI flag wired through
///    `PackageFTSCandidateFetcher.appleImport` and the per-source runner.
/// 4. `Shared.Constants.Search.schemaParamAppleImports` MCP schema
///    constant (downstream MCP threading is filed as v1.2.1 follow-up
///    because `Services.UnifiedSearchService.searchAll` doesn't yet
///    accept the param).
///
/// This suite pins the SQL pattern that the filter relies on, in
/// isolation from `PackageQuery.answer(...)`'s full BM25 + intent +
/// kind-bonus pipeline. The end-to-end behaviour is verified by the
/// spot-check after the real save runs on `~/.cupertino-dev`
/// (per the hand-off contract). The single test below proves the
/// quote-bracketed LIKE pattern is the right shape: `'%"swiftui"%'`
/// matches `'["swiftui"]'` but NOT `'["swiftuihelper"]'`.
@Suite("#837 — apple_imports_json quote-bracketed LIKE pattern", .serialized)
struct Issue837PackagesGenericConstraintsBoostTests {
    @Test("apple_imports_json LIKE '%\"swiftui\"%' matches '[\"swiftui\"]' but NOT '[\"swiftuihelper\"]'")
    func quoteBracketedLikePattern() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-837-apple-imports-sql-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.db")

        var conn: OpaquePointer?
        try #require(sqlite3_open(path.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }

        // Minimal schema mirroring package_metadata.apple_imports_json.
        let setupSQL = """
        CREATE TABLE pm (id INTEGER PRIMARY KEY AUTOINCREMENT, apple_imports_json TEXT);
        INSERT INTO pm (apple_imports_json) VALUES ('["swiftui"]');
        INSERT INTO pm (apple_imports_json) VALUES ('["swiftuihelper"]');
        INSERT INTO pm (apple_imports_json) VALUES ('["combine","swiftui"]');
        INSERT INTO pm (apple_imports_json) VALUES ('[]');
        INSERT INTO pm (apple_imports_json) VALUES (NULL);
        """
        var errPtr: UnsafeMutablePointer<CChar>?
        try #require(sqlite3_exec(conn, setupSQL, nil, nil, &errPtr) == SQLITE_OK)
        sqlite3_free(errPtr)

        // The exact pattern Search.PackageQuery uses.
        let sql = """
        SELECT apple_imports_json
        FROM pm
        WHERE apple_imports_json LIKE '%"' || ? || '"%'
        ORDER BY id;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(conn, sql, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, ("swiftui" as NSString).utf8String, -1, nil)

        var matches: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(stmt, 0) {
                matches.append(String(cString: ptr))
            }
        }

        // Exact expected behaviour:
        //  - '["swiftui"]'             → matches
        //  - '["combine","swiftui"]'   → matches (multi-element JSON
        //                                array)
        //  - '["swiftuihelper"]'       → does NOT match (the quote
        //                                brackets in the pattern prevent
        //                                the substring false-positive)
        //  - '[]'                      → does NOT match
        //  - NULL                      → does NOT match
        #expect(matches.contains("[\"swiftui\"]"))
        #expect(matches.contains("[\"combine\",\"swiftui\"]"))
        #expect(!matches.contains("[\"swiftuihelper\"]"))
        #expect(matches.count == 2)
    }
}
