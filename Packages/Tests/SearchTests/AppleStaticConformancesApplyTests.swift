import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - applyAppleStaticConformances (conformance sibling of #759 iter-3)

/// Pins the SQL apply that overwrites `doc_symbols.conformances` with the
/// authoritative Apple SDK conformance set. Mirrors the constraints apply:
/// exact `doc_uri =` match + hash-prefix `doc_uri LIKE entry.docURI || '-%'`.
@Suite("applyAppleStaticConformances (pass SQL UPDATE)", .serialized)
struct AppleStaticConformancesApplyTests {
    private struct InMemoryLookup: Search.StaticConformancesLookup {
        let entries: [Search.StaticConformanceEntry]
        func allConformanceEntries() async throws -> [Search.StaticConformanceEntry] {
            entries
        }
    }

    private static func makeFreshDB() async throws -> (dbPath: URL, index: Search.Index) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-conformances-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
        return (dbPath, index)
    }

    @discardableResult
    private static func seedSymbol(dbPath: URL, docUri: String, name: String = "Foo") throws -> Int64 {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        let metaSQL = """
        INSERT OR IGNORE INTO docs_metadata
            (uri, source, framework, language, kind, file_path, content_hash, last_crawled, word_count)
        VALUES (?, 'apple-docs', 'swiftui', 'swift', 'unknown', '/tmp/fake', '0', 0, 0);
        """
        var metaStmt: OpaquePointer?
        defer { sqlite3_finalize(metaStmt) }
        try #require(sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK)
        sqlite3_bind_text(metaStmt, 1, (docUri as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(metaStmt) == SQLITE_DONE)

        let sql = """
        INSERT INTO doc_symbols
            (doc_uri, name, kind, line, column, signature, is_async, is_throws,
             is_public, is_static, generic_params, generic_constraints)
        VALUES (?, ?, 'struct', 1, 1, NULL, 0, 0, 1, 0, NULL, NULL);
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (docUri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        return sqlite3_last_insert_rowid(db)
    }

    private static func conformances(dbPath: URL, docUri: String) throws -> String? {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, "SELECT conformances FROM doc_symbols WHERE doc_uri = ?;", -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (docUri as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }

    @Test("exact-match: stamps doc_symbols.conformances with the joined set")
    func exactMatch() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        try Self.seedSymbol(dbPath: dbPath, docUri: "apple-docs://swiftui/foreach")

        let affected = try await index.applyAppleStaticConformances(
            lookup: InMemoryLookup(entries: [
                .init(docURI: "apple-docs://swiftui/foreach", conformsTo: ["View", "Equatable"]),
            ]),
            audit: nil,
            dbPath: dbPath.path
        )
        #expect(affected >= 1)
        #expect(try Self.conformances(dbPath: dbPath, docUri: "apple-docs://swiftui/foreach") == "View,Equatable")
    }

    @Test("hash-prefix: stamps an overload row whose doc_uri carries a -<hash> suffix")
    func hashPrefixMatch() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        try Self.seedSymbol(dbPath: dbPath, docUri: "apple-docs://swiftui/foreach/init(_:content:)-7l1jb")

        let affected = try await index.applyAppleStaticConformances(
            lookup: InMemoryLookup(entries: [
                .init(docURI: "apple-docs://swiftui/foreach/init(_:content:)", conformsTo: ["View"]),
            ]),
            audit: nil,
            dbPath: dbPath.path
        )
        #expect(affected >= 1)
        #expect(try Self.conformances(dbPath: dbPath, docUri: "apple-docs://swiftui/foreach/init(_:content:)-7l1jb") == "View")
    }

    @Test("nil lookup is a no-op (0 affected, row untouched)")
    func nilLookupNoOp() async throws {
        let (dbPath, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }
        try Self.seedSymbol(dbPath: dbPath, docUri: "apple-docs://swiftui/foreach")

        let affected = try await index.applyAppleStaticConformances(lookup: nil, audit: nil, dbPath: dbPath.path)
        #expect(affected == 0)
        #expect(try Self.conformances(dbPath: dbPath, docUri: "apple-docs://swiftui/foreach") == nil)
    }
}
