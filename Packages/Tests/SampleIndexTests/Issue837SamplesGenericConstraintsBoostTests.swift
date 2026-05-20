import Foundation
import LoggingModels
@testable import SampleIndex
import SampleIndexModels
import SearchModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #837 read-side wiring — samples.db searchSymbolsForFiles consults generic_constraints

/// Pinned per `docs/design/how-cupertino-answers-a-query.md` §6.
/// `Sample.Search.Service.search` now calls
/// `Sample.Index.Database.searchSymbolsForFiles` to find files whose
/// `file_symbols` row LIKE-matches the query in name, attributes,
/// conformances, signature, or — new in this PR —
/// `generic_constraints`. Matched files get a `rank * 3.0` boost.
@Suite("#837 — Sample.Index.Database.searchSymbolsForFiles reads generic_constraints", .serialized)
struct Issue837SamplesGenericConstraintsBoostTests {
    private static func makeFreshDB() async throws -> (path: URL, db: Sample.Index.Database) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-837-samples-readside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("samples.db")
        let db = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        return (path, db)
    }

    /// Seed a project + file via the actor, then write the symbol row
    /// directly with raw SQL so we can set `generic_constraints`
    /// (which `indexSymbols` doesn't bind). Close the actor first so
    /// the writer connection isn't competing.
    @discardableResult
    private static func seedSymbol(
        at path: URL,
        db: Sample.Index.Database,
        projectId: String,
        filePath: String,
        genericConstraints: String
    ) async throws -> Int64 {
        let project = Sample.Index.Project(
            id: projectId, title: "T", description: "T",
            frameworks: ["SwiftUI"], readme: nil,
            webURL: "https://example.test/\(projectId)",
            zipFilename: "\(projectId).zip",
            fileCount: 1, totalSize: 100
        )
        try await db.indexProject(project)
        try await db.indexFile(Sample.Index.File(projectId: projectId, path: filePath, content: "// stub"))
        let fileId = try await db.getFileId(projectId: projectId, path: filePath) ?? -1
        #expect(fileId > 0)
        await db.disconnect()

        var conn: OpaquePointer?
        try #require(sqlite3_open(path.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        INSERT INTO file_symbols
            (file_id, name, kind, line, column, signature, is_async, is_throws, is_public, is_static,
             attributes, conformances, generic_params, generic_constraints)
            VALUES (?, 'IrrelevantName', 'struct', 1, 1, 'irrelevant', 0, 0, 1, 0,
                    'unrelated', 'unrelated', 'T', ?);
        """
        try #require(sqlite3_prepare_v2(conn, sql, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_int64(stmt, 1, fileId)
        sqlite3_bind_text(stmt, 2, (genericConstraints as NSString).utf8String, -1, nil)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        return fileId
    }

    // MARK: - positive

    @Test("constraint-only match — query 'View' lights up a file whose only file_symbols signal is generic_constraints='View'")
    func positiveConstraintMatch() async throws {
        let (path, db) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try await Self.seedSymbol(
            at: path, db: db,
            projectId: "demo", filePath: "Sources/Picker.swift",
            genericConstraints: "View,Hashable"
        )

        let reopened = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        defer { Task { await reopened.disconnect() } }
        let keys = try await reopened.searchSymbolsForFiles(query: "View", limit: 50)
        #expect(keys.contains("demo|Sources/Picker.swift"))
    }

    // MARK: - negative

    @Test("no false positive — query 'View' does NOT match a file whose generic_constraints is unrelated")
    func negativeNoFalsePositive() async throws {
        let (path, db) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try await Self.seedSymbol(
            at: path, db: db,
            projectId: "demo", filePath: "Sources/Foo.swift",
            genericConstraints: "Equatable,Comparable"
        )

        let reopened = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        defer { Task { await reopened.disconnect() } }
        let keys = try await reopened.searchSymbolsForFiles(query: "View", limit: 50)
        #expect(!keys.contains("demo|Sources/Foo.swift"))
    }
}
