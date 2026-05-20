import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #837 PR-2 — MCP / cross-DB read-side coverage

/// Pinned per the v1.2.0 PR-2 autopilot spec. Three new cases extend the
/// existing PR-1 (search.db + samples.db boost) + PR-2 step-1 (SQL
/// pattern) coverage to a full 8:
///
///   - `mcpFanOutPackagesSearch`     — verifies `Search.PackageQuery`'s
///     conformance to `Search.PackagesSearcher` and the
///     `Search.Result` round-trip used by the MCP `handleSearchPackages`
///     path. Pre-PR-2, MCP `source=packages` queried `search.db` and
///     returned zero rows because search.db doesn't carry `packages`
///     source values; PR-2 routes through this seam to packages.db
///     directly.
///
///   - `searchPackageSymbolsByGenericConstraintHit` — covers the `#857`
///     cross-DB search_generics fan-out's packages arm. Seeds one
///     `package_symbols` row whose `generic_constraints` contains
///     `T: View` and asserts the row comes back through
///     `searchPackageSymbolsByGenericConstraint(constraint: "View")`.
///
///   - `appleImportsFilterRestrictsResults` — end-to-end check that the
///     `--apple-imports` filter threaded through CLI → MCP → Services →
///     `Search.PackagesSearcher` actually narrows results at the SQL
///     layer. Two packages seeded with different `apple_imports_json`
///     values; query with `appleImport: "swiftui"` returns only the
///     SwiftUI package.
@Suite("#837 PR-2 — MCP cross-DB + apple-imports filter", .serialized)
struct Issue837PR2MCPCrossDBTests {
    private static func makeFreshDB() async throws -> (path: URL, index: Search.PackageIndex) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-837-pr2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("packages.db")
        let index = try await Search.PackageIndex(dbPath: path, logger: Logging.NoopRecording())
        return (path, index)
    }

    /// Seed one package with metadata + a single file + an optional
    /// `apple_imports_json` value + an optional `package_symbols` row.
    @discardableResult
    private static func seedPackage(
        at dbPath: URL,
        owner: String,
        repo: String,
        module: String,
        fileRelpath: String,
        fileContent: String,
        appleImportsJSON: String?,
        symbol: (name: String, kind: String, signature: String, genericConstraints: String?)?
    ) throws -> Int64 {
        var conn: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &conn) == SQLITE_OK)
        defer { sqlite3_close(conn) }

        // package_metadata
        var stmt: OpaquePointer?
        let pkgSQL: String
        if appleImportsJSON == nil {
            pkgSQL = """
            INSERT INTO package_metadata (owner, repo, url, fetched_at, is_apple_official)
            VALUES (?, ?, ?, ?, 0);
            """
        } else {
            pkgSQL = """
            INSERT INTO package_metadata
                (owner, repo, url, fetched_at, is_apple_official, apple_imports_json, enrichment_version)
            VALUES (?, ?, ?, ?, 0, ?, 1);
            """
        }
        try #require(sqlite3_prepare_v2(conn, pkgSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (owner as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (repo as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, ("https://example.test/\(owner)/\(repo)" as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, 0)
        if let appleImportsJSON {
            sqlite3_bind_text(stmt, 5, (appleImportsJSON as NSString).utf8String, -1, nil)
        }
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        let pkgId = sqlite3_last_insert_rowid(conn)
        sqlite3_finalize(stmt)
        stmt = nil

        // package_files
        let fileSQL = """
        INSERT INTO package_files (package_id, relpath, kind, module, size_bytes, indexed_at)
        VALUES (?, ?, 'source', ?, ?, 0);
        """
        try #require(sqlite3_prepare_v2(conn, fileSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_int64(stmt, 1, pkgId)
        sqlite3_bind_text(stmt, 2, (fileRelpath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (module as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, Int32(fileContent.utf8.count))
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        let fileId = sqlite3_last_insert_rowid(conn)
        sqlite3_finalize(stmt)
        stmt = nil

        // package_files_fts (the answer() path reads through FTS)
        let ftsSQL = """
        INSERT INTO package_files_fts
            (package_id, owner, repo, module, relpath, kind, title, content, symbols)
        VALUES (?, ?, ?, ?, ?, 'source', ?, ?, ?);
        """
        try #require(sqlite3_prepare_v2(conn, ftsSQL, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_int64(stmt, 1, pkgId)
        sqlite3_bind_text(stmt, 2, (owner as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (repo as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (module as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (fileRelpath as NSString).utf8String, -1, nil)
        let title = (fileRelpath as NSString).lastPathComponent
        sqlite3_bind_text(stmt, 6, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (fileContent as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, "", -1, nil)
        try #require(sqlite3_step(stmt) == SQLITE_DONE)
        sqlite3_finalize(stmt)
        stmt = nil

        // package_symbols (optional)
        if let symbol {
            let symSQL = """
            INSERT INTO package_symbols
                (file_id, name, kind, line, column, signature, is_async, is_throws,
                 is_public, is_static, attributes, conformances, generic_params,
                 generic_constraints, enrichment_version)
            VALUES (?, ?, ?, 1, 1, ?, 0, 0, 1, 0, NULL, NULL, NULL, ?, 1);
            """
            try #require(sqlite3_prepare_v2(conn, symSQL, -1, &stmt, nil) == SQLITE_OK)
            sqlite3_bind_int64(stmt, 1, fileId)
            sqlite3_bind_text(stmt, 2, (symbol.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (symbol.kind as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (symbol.signature as NSString).utf8String, -1, nil)
            if let constraints = symbol.genericConstraints {
                sqlite3_bind_text(stmt, 5, (constraints as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            try #require(sqlite3_step(stmt) == SQLITE_DONE)
            sqlite3_finalize(stmt)
            stmt = nil
        }

        return pkgId
    }

    // MARK: - Test 6 / 8 — MCP fan-out fix

    @Test("Search.PackageQuery.searchPackages round-trips packages.db rows as Search.Result")
    func mcpFanOutPackagesSearch() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        await index.disconnect()

        try Self.seedPackage(
            at: path,
            owner: "alpha",
            repo: "swift-charts",
            module: "Charts",
            fileRelpath: "Sources/Charts/BarChart.swift",
            fileContent: "public struct BarChart { public init() {} }",
            appleImportsJSON: nil,
            symbol: nil
        )

        let query = try await Search.PackageQuery(dbPath: path)
        defer { Task { await query.disconnect() } }

        // Use a query phrase that classifies as `symbolLookup` so the
        // intent config's `kindFilter` accepts `kind = "source"` (the
        // default `howTo` intent filters to readme/article kinds).
        let results = try await query.searchPackages(
            query: "what is the signature of BarChart",
            limit: 5,
            availability: nil,
            swiftTools: nil,
            appleImport: nil
        )

        #expect(!results.isEmpty)
        if let first = results.first {
            #expect(first.source == Shared.Constants.SourcePrefix.packages)
            #expect(first.uri.hasPrefix("\(Shared.Constants.SourcePrefix.packages)://alpha/swift-charts/"))
            #expect(first.framework == "Charts")
        }
    }

    // MARK: - Test 7 / 8 — search_generics cross-DB packages arm

    @Test("searchPackageSymbolsByGenericConstraint matches generic_constraints LIKE-pattern")
    func searchPackageSymbolsByGenericConstraintHit() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        await index.disconnect()

        try Self.seedPackage(
            at: path,
            owner: "beta",
            repo: "swift-ui-helpers",
            module: "SwiftUIHelpers",
            fileRelpath: "Sources/Helpers/AnyViewBuilder.swift",
            fileContent: "@resultBuilder public struct AnyViewBuilder {}",
            appleImportsJSON: nil,
            symbol: (
                name: "AnyViewBuilder",
                kind: "struct",
                signature: "public struct AnyViewBuilder<T>",
                genericConstraints: "T: View"
            )
        )
        try Self.seedPackage(
            at: path,
            owner: "beta",
            repo: "swift-state",
            module: "StateKit",
            fileRelpath: "Sources/State/Counter.swift",
            fileContent: "public struct Counter { public var count = 0 }",
            appleImportsJSON: nil,
            symbol: (
                name: "Counter",
                kind: "struct",
                signature: "public struct Counter",
                genericConstraints: nil
            )
        )

        let query = try await Search.PackageQuery(dbPath: path)
        defer { Task { await query.disconnect() } }

        let hits = try await query.searchPackageSymbolsByGenericConstraint(
            constraint: "View",
            framework: nil,
            limit: 20
        )

        // The View-constrained symbol matches; the Counter symbol's
        // signature contains no "View" substring and generic_constraints
        // is NULL so it stays out.
        let viewBuilderHit = hits.first { $0.title == "AnyViewBuilder" }
        #expect(viewBuilderHit != nil)
        #expect(viewBuilderHit?.framework == "SwiftUIHelpers")
        #expect(!hits.contains { $0.title == "Counter" })
    }

    // MARK: - Test 8 / 8 — apple-imports filter end-to-end

    @Test("searchPackages with appleImport=swiftui returns only packages whose apple_imports_json contains swiftui")
    func appleImportsFilterRestrictsResults() async throws {
        let (path, index) = try await Self.makeFreshDB()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        await index.disconnect()

        try Self.seedPackage(
            at: path,
            owner: "gamma",
            repo: "swiftui-charts",
            module: "Charts",
            fileRelpath: "Sources/Charts/Pie.swift",
            fileContent: "public struct Pie { public init() {} }",
            appleImportsJSON: "[\"swiftui\"]",
            symbol: nil
        )
        try Self.seedPackage(
            at: path,
            owner: "gamma",
            repo: "vapor-router",
            module: "VaporRouter",
            fileRelpath: "Sources/Router/Pie.swift",
            fileContent: "public struct Pie { public init() {} }",
            appleImportsJSON: "[\"foundation\"]",
            symbol: nil
        )

        let query = try await Search.PackageQuery(dbPath: path)
        defer { Task { await query.disconnect() } }

        // `symbolLookup` intent so `kind = "source"` rows pass the
        // intent's `kindFilter` (the `howTo` default filters to docs/
        // readme kinds and would zero out the test's `kind="source"`
        // seed regardless of the apple_imports filter).
        let unfiltered = try await query.searchPackages(
            query: "signature of Pie",
            limit: 10,
            availability: nil,
            swiftTools: nil,
            appleImport: nil
        )
        let filtered = try await query.searchPackages(
            query: "signature of Pie",
            limit: 10,
            availability: nil,
            swiftTools: nil,
            appleImport: "swiftui"
        )

        #expect(unfiltered.count >= 2)
        #expect(filtered.count == 1)
        if let only = filtered.first {
            #expect(only.uri.contains("swiftui-charts"))
            #expect(!only.uri.contains("vapor-router"))
        }
    }
}
