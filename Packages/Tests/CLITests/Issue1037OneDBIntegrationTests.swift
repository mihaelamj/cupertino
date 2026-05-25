import Foundation
import LoggingModels
import SampleIndexModels
import SampleIndexSQLite
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import SQLite3
import Testing

// MARK: - #1037 one-DB integration tests

/// End-to-end proof of the post-#1037 design target: ONE physical
/// SQLite file (`apple-sample-code.db`) holds two independent table
/// tracks (Sample.Index.Builder's rich schema + Search.Index's FTS
/// schema), both writable + readable without one trampling the other.
///
/// The arc's earlier commits each pinned one piece of this in
/// isolation:
/// - `ce4605d` got Sample.Index off PRAGMA user_version so it doesn't
///   trample Search.Index's version stamp.
/// - `ffec318` made the migrator's writer factory preserve a file
///   that carries Sample.Index tables instead of wiping it.
/// - Multiple round-5 + round-6 fixes (`418550c` et al.) hardened the
///   wipe-decision around corruption + foreign PRAGMA leaks.
///
/// This suite is the load-bearing claim test: drive both pipelines
/// against the same path in both possible orders (Sample first then
/// Search, Search first then Sample), close, re-open, verify both
/// table tracks survive with their data intact.
@Suite("#1037: one DB, two table tracks (Sample.Index + Search.Index coexistence)")
struct Issue1037OneDBIntegrationTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue1037-one-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeSampleProject(id: String) -> Sample.Index.Project {
        Sample.Index.Project(
            id: id,
            title: "Project \(id)",
            description: "Integration-test project for #1037",
            frameworks: ["SwiftUI"],
            readme: nil,
            webURL: "https://example.test/\(id)",
            zipFilename: "\(id).zip",
            fileCount: 0,
            totalSize: 0
        )
    }

    private func makeSearchDoc(uri: String) -> Search.IndexDocumentParams {
        Search.IndexDocumentParams(
            uri: uri,
            source: "apple-docs",
            framework: "TestFramework",
            language: "swift",
            title: "Title for \(uri)",
            content: "Body content for the integration test doc at \(uri).",
            filePath: "/tmp/\(uri)",
            contentHash: "hash-\(uri)",
            lastCrawled: Date()
        )
    }

    // MARK: - Helpers reading the on-disk file directly

    /// Read a scalar value (string-cast) from an arbitrary SQL query.
    /// Used to inspect the two table tracks without opening the actor.
    private func readScalar(at dbPath: URL, sql: String) throws -> String? {
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if let ptr = sqlite3_column_text(stmt, 0) {
            return String(cString: ptr)
        }
        return nil
    }

    // MARK: - Order 1: Sample.Index writes first, then Search.Index

    @Test("Sample.Index writes first, Search.Index opens after: both tracks survive with full data")
    func sampleFirstSearchSecondCoexistence() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = Sample.Index.databasePath(baseDirectory: dir)

        // Phase 1: Sample.Index writes rich-schema data.
        let sampleFirst = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        try await sampleFirst.indexProject(makeSampleProject(id: "sample-only-1"))
        try await sampleFirst.indexProject(makeSampleProject(id: "sample-only-2"))
        await sampleFirst.disconnect()
        #expect(try readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "2")
        #expect(try readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == "4")

        // Phase 2: Search.Index opens the same file. The preserve-on-
        // foreign-tables path (#1037 part 3) means Search.Index must
        // NOT wipe the Sample.Index data; createTables IF NOT EXISTS
        // adds docs_metadata + docs_fts alongside the existing tables.
        let searchAfter = try await Search.Index(
            dbPath: path,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await searchAfter.indexDocument(makeSearchDoc(uri: "ad://a"))
        try await searchAfter.indexDocument(makeSearchDoc(uri: "ad://b"))
        try await searchAfter.indexDocument(makeSearchDoc(uri: "ad://c"))
        await searchAfter.disconnect()

        // Phase 3: re-open both, verify all data survived.
        // Sample.Index reads its tracking table; wipeIfStale must NOT
        // fire because the populated row matches schemaVersion.
        let sampleReopen = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        let projectCount = try await sampleReopen.projectCount()
        #expect(projectCount == 2, "Sample.Index projects must survive Search.Index writing alongside")
        await sampleReopen.disconnect()

        let searchReopen = try await Search.Index(
            dbPath: path,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        let docCount = try await searchReopen.documentCount()
        #expect(docCount == 3, "Search.Index documents must survive Sample.Index re-opening alongside")
        await searchReopen.disconnect()

        // Belt + braces: also verify via raw sqlite3 that both table
        // sets coexist with their full row counts.
        #expect(try readScalar(at: path, sql: "SELECT COUNT(*) FROM projects;") == "2")
        #expect(try readScalar(at: path, sql: "SELECT COUNT(*) FROM docs_metadata;") == "3")
        // Sample.Index version stamp lives in its own table.
        #expect(try readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == "4")
        // Search.Index version stamp lives in the SQLite header PRAGMA.
        #expect(try readScalar(at: path, sql: "PRAGMA user_version;") == String(Search.Index.schemaVersion))
    }

    // MARK: - Order 2: Search.Index writes first, then Sample.Index

    @Test("Search.Index writes first, Sample.Index opens after: both tracks survive with full data")
    func searchFirstSampleSecondCoexistence() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = Sample.Index.databasePath(baseDirectory: dir)

        // Phase 1: Search.Index writes FTS-style docs.
        let searchFirst = try await Search.Index(
            dbPath: path,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await searchFirst.indexDocument(makeSearchDoc(uri: "search-only/a"))
        try await searchFirst.indexDocument(makeSearchDoc(uri: "search-only/b"))
        await searchFirst.disconnect()
        #expect(try readScalar(at: path, sql: "SELECT COUNT(*) FROM docs_metadata;") == "2")
        #expect(try readScalar(at: path, sql: "PRAGMA user_version;") == String(Search.Index.schemaVersion))

        // Phase 2: Sample.Index.Database opens the same file. The
        // refined wipe condition (#1037 part 1) checks `projects` table
        // presence FIRST (false here, Search.Index didn't create one),
        // so no wipe fires. createTables adds the rich-schema tables.
        let sampleAfter = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        try await sampleAfter.indexProject(makeSampleProject(id: "after-search-1"))
        await sampleAfter.disconnect()

        // Phase 3: re-open both. Verify the foreign PRAGMA stamp from
        // Search.Index did NOT trip Sample.Index's wipe path; the
        // populated samples_schema_version row gates the wipe-check.
        let searchReopen = try await Search.Index(
            dbPath: path,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        let docCount = try await searchReopen.documentCount()
        #expect(docCount == 2, "Search.Index documents must survive Sample.Index writing alongside")
        await searchReopen.disconnect()

        let sampleReopen = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        let projectCount = try await sampleReopen.projectCount()
        #expect(projectCount == 1)
        await sampleReopen.disconnect()

        // Both version stamps coexist.
        #expect(try readScalar(at: path, sql: "SELECT version FROM samples_schema_version LIMIT 1") == "4")
        #expect(try readScalar(at: path, sql: "PRAGMA user_version;") == String(Search.Index.schemaVersion))
    }

    // MARK: - Path identity

    @Test("Sample.Index.databasePath and SampleCodeSource.destinationDB resolve to the same on-disk file (one DB target)")
    func pathIdentityProof() throws {
        let baseDir = URL(fileURLWithPath: "/tmp/issue-1037-path-identity")
        let sampleIndexPath = Sample.Index.databasePath(baseDirectory: baseDir)
        let descriptorFilename = Shared.Models.DatabaseDescriptor.appleSampleCode.filename
        let descriptorPath = baseDir.appendingPathComponent(descriptorFilename)
        let message = "Sample.Index pipeline and SampleCodeSource (FTS) pipeline must target the same physical file. " +
            "Got Sample.Index.databasePath=\(sampleIndexPath.path), descriptor=\(descriptorPath.path)."
        #expect(sampleIndexPath.path == descriptorPath.path, Comment(rawValue: message))
        #expect(sampleIndexPath.lastPathComponent == "apple-sample-code.db")
    }

    // MARK: - Re-write idempotence (the simulated `cupertino save --all` re-run)

    @Test("Re-running both pipelines against the existing one-DB shape preserves prior data and adds new rows")
    func reRunPreservesAndExtends() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = Sample.Index.databasePath(baseDirectory: dir)

        // First pass: write 1 project + 1 doc.
        let s1 = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        try await s1.indexProject(makeSampleProject(id: "first"))
        await s1.disconnect()
        let d1 = try await Search.Index(
            dbPath: path,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await d1.indexDocument(makeSearchDoc(uri: "first/doc"))
        await d1.disconnect()

        // Second pass: write 1 more project + 1 more doc. No --clear,
        // so existing rows must persist.
        let s2 = try await Sample.Index.Database(dbPath: path, logger: Logging.NoopRecording())
        try await s2.indexProject(makeSampleProject(id: "second"))
        let secondCount = try await s2.projectCount()
        #expect(secondCount == 2, "First-pass project must survive the second-pass open + indexProject")
        await s2.disconnect()

        let d2 = try await Search.Index(
            dbPath: path,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await d2.indexDocument(makeSearchDoc(uri: "second/doc"))
        let docCount = try await d2.documentCount()
        #expect(docCount == 2, "First-pass doc must survive the second-pass Search.Index open + indexDocument")
        await d2.disconnect()
    }
}
