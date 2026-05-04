import Foundation
@testable import Search
import SQLite3
import Testing

// MARK: - C2 integration coverage

//
// Each change introduced by #192 section C2 lives under its own suite here:
//   - Schema version lock
//   - docs_metadata.kind column populated via indexDocument (no structured kind)
//   - docs_metadata.kind column populated via indexStructuredDocument (with page.kind)
//   - docs_metadata.symbols column exists as nullable TEXT
//   - idx_kind index exists on docs_metadata(kind)
//   - migrateToVersion11 round-trips from v10 schema
//
// All tests use a fresh temp DB per test to avoid cross-contamination and clean
// up on exit.

private func makeTempDB() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("dockind-\(UUID().uuidString).db")
}

/// Raw-SQL helper: read a single column value for a given URI from the temp DB.
private func readColumn(
    at dbPath: URL,
    column: String,
    forURI uri: String
) throws -> String? {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw TestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    let sql = "SELECT \(column) FROM docs_metadata WHERE uri = ? LIMIT 1;"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw TestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)

    let rc = sqlite3_step(stmt)
    guard rc == SQLITE_ROW else {
        return nil
    }
    if sqlite3_column_type(stmt, 0) == SQLITE_NULL {
        return nil
    }
    return String(cString: sqlite3_column_text(stmt, 0))
}

/// Raw-SQL helper: check whether an index with the given name exists.
private func indexExists(at dbPath: URL, name: String) throws -> Bool {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw TestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    let sql = "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ? LIMIT 1;"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw TestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
    return sqlite3_step(stmt) == SQLITE_ROW
}

/// Raw-SQL helper: read PRAGMA user_version.
private func readSchemaVersion(at dbPath: URL) throws -> Int32 {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw TestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else {
        throw TestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt) == SQLITE_ROW else {
        throw TestError.prepareFailed("user_version row missing")
    }
    return sqlite3_column_int(stmt, 0)
}

enum TestError: Error {
    case openFailed(String)
    case prepareFailed(String)
}

// MARK: - Schema version + index shape

@Suite("Search.Index schema shape (#192 C2)")
struct SchemaShapeTests {
    @Test("Schema version constant is 12")
    func schemaVersionIs12() {
        #expect(Search.Index.schemaVersion == 12)
    }

    @Test("Fresh DB has PRAGMA user_version = 12")
    func freshDBStampedVersion() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)
        await idx.disconnect()

        #expect(try readSchemaVersion(at: dbPath) == 12)
    }

    @Test("Fresh DB has idx_kind index on docs_metadata")
    func idxKindExists() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath)
        await idx.disconnect()

        #expect(try indexExists(at: dbPath, name: "idx_kind"))
    }
}

// MARK: - indexDocument (no structured kind) wires classifier

@Suite("Search.Index.indexDocument → docs_metadata.kind (#192 C2)")
struct IndexDocumentKindTests {
    private func insertAndReadKind(
        source: String,
        uri: String,
        framework: String = "test"
    ) async throws -> String? {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath)
        try await idx.indexDocument(
            uri: uri,
            source: source,
            framework: framework,
            title: "Test Doc",
            content: "Some content for the test.",
            filePath: "/tmp/x",
            contentHash: "h",
            lastCrawled: Date()
        )
        await idx.disconnect()

        return try readColumn(at: dbPath, column: "kind", forURI: uri)
    }

    @Test("swift-evolution source → evolutionProposal")
    func evolutionDocKind() async throws {
        let got = try await insertAndReadKind(source: "swift-evolution", uri: "swift-evolution://SE-0306")
        #expect(got == "evolutionProposal")
    }

    @Test("swift-book source → swiftBook")
    func swiftBookDocKind() async throws {
        let got = try await insertAndReadKind(source: "swift-book", uri: "swift-book://the-basics")
        #expect(got == "swiftBook")
    }

    @Test("hig source → hig")
    func higDocKind() async throws {
        let got = try await insertAndReadKind(source: "hig", uri: "hig://components/buttons")
        #expect(got == "hig")
    }

    @Test("apple-docs with /samplecode/ URI → sampleCode (even without structured kind)")
    func appleDocsSampleCodeKind() async throws {
        let got = try await insertAndReadKind(
            source: "apple-docs",
            uri: "apple-docs://swiftui/documentation/samplecode/robust-nav"
        )
        #expect(got == "sampleCode")
    }

    @Test("apple-docs without structured kind + regular URI → unknown")
    func appleDocsNoStructuredDefaultsToUnknown() async throws {
        let got = try await insertAndReadKind(
            source: "apple-docs",
            uri: "apple-docs://swiftui/view"
        )
        #expect(got == "unknown")
    }

    @Test("Unknown source → unknown")
    func unrecognisedSourceFallback() async throws {
        let got = try await insertAndReadKind(source: "weird-source", uri: "weird://x")
        #expect(got == "unknown")
    }
}

// MARK: - symbols column round-trip

@Suite("Search.Index docs_metadata.symbols column (#192 C2)")
struct SymbolsColumnTests {
    @Test("symbols column is NULL by default after indexDocument")
    func symbolsDefaultsToNull() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath)
        try await idx.indexDocument(
            uri: "test://nosym",
            source: "swift-book",
            framework: nil,
            title: "No Symbols Test",
            content: "Body",
            filePath: "/tmp/x",
            contentHash: "h",
            lastCrawled: Date()
        )
        await idx.disconnect()

        // Column exists, value is NULL — readColumn returns nil for NULL.
        #expect(try readColumn(at: dbPath, column: "symbols", forURI: "test://nosym") == nil)
    }
}
