import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #837 — packages apple-imports aggregation coverage

/// Pinned per `docs/design/837-pre-index-test-plan.md` §9.4 cases i1-i5.
/// Subject under test:
/// - `Search.PackageIndex.applyAppleImports(lookup:enrichmentVersion:)`
@Suite("#837 — Search.PackageIndex.applyAppleImports", .serialized)
struct Issue837PackagesAppleImportsTests {
    private struct InMemoryLookup: Search.StaticConstraintsLookup {
        let entries: [Search.StaticConstraintEntry]
        func allEntries() async throws -> [Search.StaticConstraintEntry] {
            entries
        }
    }

    private static func makeFreshDB() async throws -> (path: URL, index: Search.PackageIndex) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-837-imports-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("packages.db")
        let index = try await Search.PackageIndex(dbPath: path, logger: Logging.NoopRecording())
        return (path, index)
    }

    /// Seed one package with one file per `modules` entry, and ALSO
    /// seed `package_imports` rows so the post-#860 `applyAppleImports`
    /// join finds something. The legacy parameter name `modules` is
    /// retained for source compatibility with i1/i2/i3/i4/i5 case
    /// authors; semantically it now represents "the `import X`
    /// statements that the package's source carries", which is the
    /// correct shape for "frameworks this package imports".
    ///
    /// Pre-#860: this helper only seeded `package_files.module`, which
    /// was the wrong RHS for the apple-imports join (it carried the
    /// package's OWN Swift module name, not the imported framework
    /// set). Post-#860: the helper seeds `package_imports.module_name`
    /// in addition; the legacy `package_files.module` write stays so
    /// existing assertions about the column's shape (NULL passthrough,
    /// case preservation) continue to hold.
    @discardableResult
    private static func seedPackage(
        at dbPath: URL,
        owner: String,
        repo: String,
        modules: [String?]
    ) throws -> Int64 {
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
        sqlite3_bind_text(stmt, 1, (owner as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (repo as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, ("https://example.test/\(owner)/\(repo)" as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, 0)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        let pkgId = sqlite3_last_insert_rowid(conn)
        sqlite3_finalize(stmt)
        stmt = nil

        for (idx, module) in modules.enumerated() {
            let fileSQL = """
            INSERT INTO package_files (package_id, relpath, kind, module, size_bytes, indexed_at)
            VALUES (?, ?, 'source', ?, 100, 0);
            """
            try #require(sqlite3_prepare_v2(conn, fileSQL, -1, &stmt, nil) == SQLITE_OK)
            sqlite3_bind_int64(stmt, 1, pkgId)
            sqlite3_bind_text(stmt, 2, ("Sources/File\(idx).swift" as NSString).utf8String, -1, nil)
            if let module {
                sqlite3_bind_text(stmt, 3, (module as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            try #require(sqlite3_step(stmt) == SQLITE_DONE)
            let fileId = sqlite3_last_insert_rowid(conn)
            sqlite3_finalize(stmt)
            stmt = nil

            // #860 — also seed the per-file import row that the
            // post-fix apple-imports pass joins against. NULL module
            // → no import row (mirrors the production behaviour where
            // the AST extractor returns an empty `imports` array for
            // files that don't declare any `import X`).
            if let module {
                let impSQL = """
                INSERT INTO package_imports (file_id, module_name, line, is_exported)
                VALUES (?, ?, 1, 0);
                """
                try #require(sqlite3_prepare_v2(conn, impSQL, -1, &stmt, nil) == SQLITE_OK)
                sqlite3_bind_int64(stmt, 1, fileId)
                sqlite3_bind_text(stmt, 2, (module as NSString).utf8String, -1, nil)
                try #require(sqlite3_step(stmt) == SQLITE_DONE)
                sqlite3_finalize(stmt)
                stmt = nil
            }
        }

        return pkgId
    }

    private static func readAppleImports(at dbPath: URL, owner: String, repo: String) throws -> (json: String?, version: Int32?) {
        var conn: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }
        let sql = "SELECT apple_imports_json, enrichment_version FROM package_metadata WHERE owner = ? AND repo = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(conn, sql, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (owner as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (repo as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (nil, nil) }
        let json = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        let versionCol: Int32? = sqlite3_column_type(stmt, 1) == SQLITE_NULL
            ? nil
            : sqlite3_column_int(stmt, 1)
        return (json, versionCol)
    }

    private static func appleLookup() -> InMemoryLookup {
        InMemoryLookup(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/view", constraints: []),
            Search.StaticConstraintEntry(docURI: "apple-docs://combine/publisher", constraints: []),
        ])
    }

    // MARK: - i1: happy path

    @Test("i1: package with SwiftUI + Combine + ThirdParty yields sorted lowercased Apple subset")
    func i1HappyPath() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedPackage(at: path, owner: "alpha", repo: "pkg", modules: ["SwiftUI", "Combine", "ThirdPartyHelper"])
        let affected = try await index.applyAppleImports(lookup: Self.appleLookup(), enrichmentVersion: 1)
        #expect(affected == 1)
        let result = try Self.readAppleImports(at: path, owner: "alpha", repo: "pkg")
        #expect(result.json == "[\"combine\",\"swiftui\"]")
        #expect(result.version == 1)
    }

    // MARK: - i2: nil lookup

    @Test("i2: nil lookup is a no-op")
    func i2NilLookup() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedPackage(at: path, owner: "alpha", repo: "pkg", modules: ["SwiftUI"])
        let nilLookup: (any Search.StaticConstraintsLookup)? = nil
        let affected = try await index.applyAppleImports(lookup: nilLookup, enrichmentVersion: 1)
        #expect(affected == 0)
        let result = try Self.readAppleImports(at: path, owner: "alpha", repo: "pkg")
        #expect(result.json == nil)
        #expect(result.version == nil)
    }

    // MARK: - i3: package with no Apple imports

    @Test("i3: package whose only modules are non-Apple stays NULL")
    func i3NoAppleImports() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedPackage(at: path, owner: "alpha", repo: "pkg", modules: ["ThirdPartyHelper"])
        let affected = try await index.applyAppleImports(lookup: Self.appleLookup(), enrichmentVersion: 1)
        // Returns 0 affected, row's apple_imports_json stays NULL.
        #expect(affected == 0)
        let result = try Self.readAppleImports(at: path, owner: "alpha", repo: "pkg")
        #expect(result.json == nil)
    }

    // MARK: - i4: multi-package isolation

    @Test("i4: a package with no Apple imports is untouched when a sibling package has them")
    func i4MultiPackageIsolation() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedPackage(at: path, owner: "alpha", repo: "pkg-apple", modules: ["SwiftUI"])
        try Self.seedPackage(at: path, owner: "beta", repo: "pkg-third", modules: ["ThirdPartyHelper"])
        let affected = try await index.applyAppleImports(lookup: Self.appleLookup(), enrichmentVersion: 1)
        #expect(affected == 1)
        let appleResult = try Self.readAppleImports(at: path, owner: "alpha", repo: "pkg-apple")
        #expect(appleResult.json == "[\"swiftui\"]")
        let thirdResult = try Self.readAppleImports(at: path, owner: "beta", repo: "pkg-third")
        #expect(thirdResult.json == nil)
    }

    // MARK: - i5: NULL module values

    @Test("i5: NULL module rows are ignored, no crash, no spurious entries")
    func i5NullModules() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Self.seedPackage(at: path, owner: "alpha", repo: "pkg", modules: ["SwiftUI", nil, nil])
        let affected = try await index.applyAppleImports(lookup: Self.appleLookup(), enrichmentVersion: 1)
        #expect(affected == 1)
        let result = try Self.readAppleImports(at: path, owner: "alpha", repo: "pkg")
        #expect(result.json == "[\"swiftui\"]")
    }
}
