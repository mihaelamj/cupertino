import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #837 — packages constraint-application write-path coverage

/// Pinned per `docs/design/837-pre-index-test-plan.md` §9.3 cases p1-p6.
/// Parallel to the samples test suite (§9.2) but writes to packages.db's
/// `package_symbols.generic_constraints` column instead of samples'
/// `file_symbols.generic_constraints`. The SQL is written separately
/// in `Packages/Sources/Search/PackageIndex.swift`; this suite catches
/// divergence from the samples implementation.
///
/// Subject under test:
/// - `Search.PackageIndex.applyAppleStaticConstraints(lookup:enrichmentVersion:)`
@Suite("#837 — Search.PackageIndex.applyAppleStaticConstraints", .serialized)
struct Issue837PackagesAppleStaticConstraintsTests {
    private struct InMemoryLookup: Search.StaticConstraintsLookup {
        let entries: [Search.StaticConstraintEntry]
        func allEntries() async throws -> [Search.StaticConstraintEntry] {
            entries
        }
    }

    private static func makeFreshDB() async throws -> (path: URL, index: Search.PackageIndex) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-837-packages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("packages.db")
        let index = try await Search.PackageIndex(dbPath: path, logger: Logging.NoopRecording())
        return (path, index)
    }

    /// Seed one row in `package_metadata`, one in `package_files`, one
    /// in `package_symbols`. Raw SQL because `Search.PackageIndex` is
    /// designed for the indexer's `index(resolved:extraction:...)`
    /// shape; for unit-test fixtures we go around the public surface.
    @discardableResult
    private static func seedSymbol(at dbPath: URL, symbolName: String) throws -> (pkgId: Int64, fileId: Int64, symbolId: Int64) {
        var conn: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let pkgSQL = """
        INSERT INTO package_metadata (owner, repo, url, fetched_at, is_apple_official)
        VALUES (?, ?, ?, ?, 0);
        """
        try #require(sqlite3_prepare_v2(conn, pkgSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, ("owner" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, ("repo" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, ("https://example.test/owner/repo" as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, 0)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        let pkgId = sqlite3_last_insert_rowid(conn)
        sqlite3_finalize(stmt)
        stmt = nil

        let fileSQL = """
        INSERT INTO package_files (package_id, relpath, kind, module, size_bytes, indexed_at)
        VALUES (?, ?, 'source', 'TestModule', 100, 0);
        """
        try #require(sqlite3_prepare_v2(conn, fileSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_int64(stmt, 1, pkgId)
        sqlite3_bind_text(stmt, 2, ("Sources/Foo.swift" as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        let fileId = sqlite3_last_insert_rowid(conn)
        sqlite3_finalize(stmt)
        stmt = nil

        let symSQL = """
        INSERT INTO package_symbols
        (file_id, name, kind, line, column, is_async, is_throws, is_public, is_static)
        VALUES (?, ?, 'structDecl', 1, 1, 0, 0, 1, 0);
        """
        try #require(sqlite3_prepare_v2(conn, symSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_int64(stmt, 1, fileId)
        sqlite3_bind_text(stmt, 2, (symbolName as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        let symbolId = sqlite3_last_insert_rowid(conn)

        return (pkgId, fileId, symbolId)
    }

    private static func readEnrichment(
        at dbPath: URL,
        name: String
    ) throws -> (constraints: String?, version: Int32?) {
        var conn: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }
        let sql = "SELECT generic_constraints, enrichment_version FROM package_symbols WHERE name = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(conn, sql, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (nil, nil) }
        let constraints = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        let versionCol: Int32? = sqlite3_column_type(stmt, 1) == SQLITE_NULL
            ? nil
            : sqlite3_column_int(stmt, 1)
        return (constraints, versionCol)
    }

    // MARK: - p1: happy path

    @Test("p1: matches lowercased name to last URI segment, writes constraints + enrichment_version")
    func p1HappyPath() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedSymbol(at: path, symbolName: "Picker")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(
                docURI: "apple-docs://swiftui/picker",
                constraints: ["View", "Hashable"]
            ),
        ])
        let affected = try await index.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(affected == 1)
        let result = try Self.readEnrichment(at: path, name: "Picker")
        #expect(result.constraints == "View,Hashable")
        #expect(result.version == 1)
    }

    // MARK: - p2: nil lookup

    @Test("p2: nil lookup is a no-op, returns 0, row untouched")
    func p2NilLookup() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedSymbol(at: path, symbolName: "Picker")
        let nilLookup: (any Search.StaticConstraintsLookup)? = nil
        let affected = try await index.applyAppleStaticConstraints(lookup: nilLookup, enrichmentVersion: 1)
        #expect(affected == 0)
        let result = try Self.readEnrichment(at: path, name: "Picker")
        #expect(result.constraints == nil)
        #expect(result.version == nil)
    }

    // MARK: - p3: empty entries

    @Test("p3: empty entries list is a no-op")
    func p3EmptyEntries() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedSymbol(at: path, symbolName: "Picker")
        let lookup = InMemoryLookup(entries: [])
        let affected = try await index.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(affected == 0)
        let result = try Self.readEnrichment(at: path, name: "Picker")
        #expect(result.constraints == nil)
    }

    // MARK: - p4: no matching rows

    @Test("p4: symbol name with no matching lookup entry is untouched")
    func p4NonMatchingName() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedSymbol(at: path, symbolName: "MyCustomType")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/picker", constraints: ["View"]),
        ])
        let affected = try await index.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(affected == 0)
        let result = try Self.readEnrichment(at: path, name: "MyCustomType")
        #expect(result.constraints == nil)
    }

    // MARK: - p5: idempotency

    @Test("p5: second run with same lookup at same version reports same affected count, values stable")
    func p5IdempotencyAtSameVersion() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedSymbol(at: path, symbolName: "Picker")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/picker", constraints: ["View"]),
        ])
        let first = try await index.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(first == 1)
        let second = try await index.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(second == 1)
        let result = try Self.readEnrichment(at: path, name: "Picker")
        #expect(result.constraints == "View")
        #expect(result.version == 1)
    }

    // MARK: - p6: case-insensitive matching

    @Test("p6: lookup matching is case-insensitive against URI last segment")
    func p6CaseInsensitiveMatching() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedSymbol(at: path, symbolName: "NAVIGATIONLINK")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/navigationlink", constraints: ["View"]),
        ])
        let affected = try await index.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(affected == 1)
        let result = try Self.readEnrichment(at: path, name: "NAVIGATIONLINK")
        #expect(result.constraints == "View")
    }
}
