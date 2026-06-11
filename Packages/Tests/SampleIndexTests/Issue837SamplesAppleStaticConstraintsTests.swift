import ASTIndexer
import Foundation
import LoggingModels
@testable import SampleIndex
import SampleIndexModels
import SampleIndexSQLite
import SearchModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #837 — samples enrichment write-path coverage

/// Pinned per `docs/design/837-pre-index-test-plan.md` §9.2 cases s1-s6.
/// Each case carries a "why this case matters" justification in the
/// design doc; if a test here fails, the relevant case in §9.2 explains
/// the production failure mode it was guarding against.
///
/// Subject under test:
/// - `Sample.Index.Database.applyAppleStaticConstraints(lookup:enrichmentVersion:)`
///   in `Packages/Sources/SampleIndex/Sample.Index.Database.swift`.
@Suite("#837 — Sample.Index.Database.applyAppleStaticConstraints", .serialized)
struct Issue837SamplesAppleStaticConstraintsTests {
    // MARK: - Test fixtures

    private struct InMemoryLookup: Search.StaticConstraintsLookup {
        let entries: [Search.StaticConstraintEntry]
        func allEntries() async throws -> [Search.StaticConstraintEntry] {
            entries
        }
    }

    private static func makeFreshDB() async throws -> (path: URL, db: Sample.Index.Database) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-837-samples-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("samples.db")
        let db = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        return (path, db)
    }

    @discardableResult
    private static func seedSymbol(
        in db: Sample.Index.Database,
        projectId: String = "test",
        filePath: String = "Sources/Foo.swift",
        symbolName: String,
        symbolKind: ASTIndexer.SymbolKind = .struct
    ) async throws -> Int64 {
        let project = Sample.Index.Project(
            id: projectId,
            title: "T",
            description: "T",
            frameworks: ["SwiftUI"],
            readme: nil,
            webURL: "https://example.test/\(projectId)",
            zipFilename: "\(projectId).zip",
            fileCount: 1,
            totalSize: 100
        )
        try await db.indexProject(project)

        let file = Sample.Index.File(
            projectId: projectId,
            path: filePath,
            content: "// stub"
        )
        try await db.indexFile(file)
        let fileId = try await db.getFileId(projectId: projectId, path: filePath) ?? -1
        #expect(fileId > 0)

        let symbol = ASTIndexer.Symbol(
            name: symbolName,
            kind: symbolKind,
            line: 1,
            column: 1,
            signature: nil,
            isAsync: false,
            isThrows: false,
            isPublic: true,
            isStatic: false,
            attributes: [],
            conformances: [],
            genericParameters: []
        )
        try await db.indexSymbols(fileId: fileId, symbols: [symbol])
        return fileId
    }

    private static func readEnrichment(
        at dbPath: URL,
        name: String
    ) throws -> (constraints: String?, version: Int32?) {
        var conn: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }
        let sql = "SELECT generic_constraints, enrichment_version FROM file_symbols WHERE name = ? LIMIT 1;"
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

    // MARK: - s1: happy path

    @Test("s1: matches lowercased name to last URI segment, writes constraints + enrichment_version")
    func s1HappyPath() async throws {
        let (path, db) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try await Self.seedSymbol(in: db, symbolName: "Picker")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(
                docURI: "apple-docs://swiftui/picker",
                constraints: ["View", "Hashable"]
            ),
        ])
        let affected = try await db.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(affected == 1)
        let result = try Self.readEnrichment(at: path, name: "Picker")
        #expect(result.constraints == "View,Hashable")
        #expect(result.version == 1)
    }

    // MARK: - s2: nil lookup

    @Test("s2: nil lookup is a no-op, returns 0, row untouched")
    func s2NilLookup() async throws {
        let (path, db) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try await Self.seedSymbol(in: db, symbolName: "Picker")
        let nilLookup: (any Search.StaticConstraintsLookup)? = nil
        let affected = try await db.applyAppleStaticConstraints(lookup: nilLookup, enrichmentVersion: 1)
        #expect(affected == 0)
        let result = try Self.readEnrichment(at: path, name: "Picker")
        #expect(result.constraints == nil)
        #expect(result.version == nil)
    }

    // MARK: - s3: empty entries

    @Test("s3: empty entries list is a no-op, returns 0, row untouched")
    func s3EmptyEntries() async throws {
        let (path, db) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try await Self.seedSymbol(in: db, symbolName: "Picker")
        let lookup = InMemoryLookup(entries: [])
        let affected = try await db.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(affected == 0)
        let result = try Self.readEnrichment(at: path, name: "Picker")
        #expect(result.constraints == nil)
    }

    // MARK: - s4: no matching rows

    @Test("s4: symbol name with no matching lookup entry is untouched")
    func s4NonMatchingName() async throws {
        let (path, db) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try await Self.seedSymbol(in: db, symbolName: "MyCustomType")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/picker", constraints: ["View"]),
        ])
        let affected = try await db.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(affected == 0)
        let result = try Self.readEnrichment(at: path, name: "MyCustomType")
        #expect(result.constraints == nil)
    }

    // MARK: - s5: idempotency

    @Test("s5: second run with same lookup at same version still reports the row, values stable")
    func s5IdempotencyAtSameVersion() async throws {
        let (path, db) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try await Self.seedSymbol(in: db, symbolName: "Picker")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/picker", constraints: ["View"]),
        ])
        let first = try await db.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(first == 1)
        let second = try await db.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        // Pin current behaviour: UPDATE on a matching row reports 1
        // even when the new values equal the old. This is the SQLite
        // sqlite3_changes() default; idempotency is value-level, not
        // row-count-level.
        #expect(second == 1)
        let result = try Self.readEnrichment(at: path, name: "Picker")
        #expect(result.constraints == "View")
        #expect(result.version == 1)
    }

    // MARK: - s6: case-insensitive matching

    @Test("s6: lookup matching is case-insensitive against URI last segment")
    func s6CaseInsensitiveMatching() async throws {
        let (path, db) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try await Self.seedSymbol(in: db, symbolName: "NAVIGATIONLINK")
        let lookup = InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/navigationlink", constraints: ["View"]),
        ])
        let affected = try await db.applyAppleStaticConstraints(lookup: lookup, enrichmentVersion: 1)
        #expect(affected == 1)
        let result = try Self.readEnrichment(at: path, name: "NAVIGATIONLINK")
        #expect(result.constraints == "View")
    }
}
