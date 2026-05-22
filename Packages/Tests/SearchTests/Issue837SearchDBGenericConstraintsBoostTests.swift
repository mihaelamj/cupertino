import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #837 read-side wiring — search.db symbol-boost picks up generic_constraints

/// Pinned per `docs/design/how-cupertino-answers-a-query.md` §6.
/// Before this PR, `Search.Index.searchSymbolsForURIs` queried
/// `doc_symbols` on name / attributes / conformances / signature but
/// NOT on `generic_constraints`. Even though #759 iter 3 populates
/// `doc_symbols.generic_constraints` at index time, no read path
/// consulted it — so a query like "View" did not light up rows that
/// had no inline mention of "View" but DID have it in their
/// constraints column. This suite covers the new branch.
@Suite("#837 — search.db searchSymbolsForURIs reads generic_constraints", .serialized)
struct Issue837SearchDBGenericConstraintsBoostTests {
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-837-search-readside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Seed one row in `docs_metadata` + one in `doc_symbols`. The
    /// symbol's `name / attributes / conformances / signature` are
    /// kept short and unrelated to the test query; `generic_constraints`
    /// carries the test query value. So the only way the symbol-boost
    /// can find this row is via the new clause.
    @discardableResult
    private static func seedRow(
        at dbPath: URL,
        uri: String,
        constraints: String?
    ) throws -> Int64 {
        var conn: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let metaSQL = """
        INSERT OR IGNORE INTO docs_metadata
            (uri, source, framework, language, kind, file_path, content_hash, last_crawled, word_count)
            VALUES (?, 'apple-docs', 'swiftui', 'swift', 'struct', '/tmp/fake', '0', 0, 0);
        """
        try #require(sqlite3_prepare_v2(conn, metaSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        sqlite3_finalize(stmt)
        stmt = nil

        let symSQL = """
        INSERT INTO doc_symbols
            (doc_uri, name, kind, line, column, signature, is_async, is_throws, is_public, is_static,
             attributes, conformances, generic_params, generic_constraints)
            VALUES (?, 'IrrelevantName', 'struct', 1, 1, 'irrelevant signature', 0, 0, 1, 0,
                    'unrelated', 'unrelated', 'T', ?);
        """
        try #require(sqlite3_prepare_v2(conn, symSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        if let constraints {
            sqlite3_bind_text(stmt, 2, (constraints as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        return sqlite3_last_insert_rowid(conn)
    }

    // MARK: - positive: row whose constraint matches the query is returned

    @Test("constraint-only match — query 'View' lights up a row whose only signal is generic_constraints='View'")
    func positiveConstraintMatch() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: path, logger: Logging.NoopRecording())
        try Self.seedRow(at: path, uri: "apple-docs://swiftui/picker", constraints: "View,Hashable")

        let uris = try await index.searchSymbolsForURIs(query: "View", limit: 50)
        #expect(uris.contains("apple-docs://swiftui/picker"))
        await index.disconnect()
    }

    // MARK: - negative: no false positive from generic_constraints

    @Test("no false positive — query 'View' does NOT match a row whose generic_constraints is unrelated")
    func negativeNoFalsePositive() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: path, logger: Logging.NoopRecording())
        try Self.seedRow(at: path, uri: "apple-docs://swiftui/foo", constraints: "Equatable,Comparable")

        let uris = try await index.searchSymbolsForURIs(query: "View", limit: 50)
        #expect(!uris.contains("apple-docs://swiftui/foo"))
        await index.disconnect()
    }
}
