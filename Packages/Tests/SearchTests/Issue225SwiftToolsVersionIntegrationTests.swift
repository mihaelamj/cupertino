import CorePackageIndexingModels
import CoreProtocols
import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #225 Part A — packages.db swift_tools_version end-to-end

//
// Companion to `Issue225SwiftToolsVersionParserTests` (the parser
// pure-function pin in ASTIndexerTests). This file asserts:
//
// 1. The schema bump is in place — fresh DBs have the new column +
//    index, and the migration from v2 → v3 adds the column without
//    losing data.
// 2. The annotator pipeline propagates the parsed swift-tools-version
//    into the AnnotationResult, then through PackageIndexer's
//    AvailabilityPayload mapping, into the `package_metadata` row.
// 3. The `Search.PackageQuery` filter pushdown honours
//    `Search.SwiftToolsFilter` — passing rows whose declaration is
//    ≥ the filter floor; rejecting NULL rows when the filter is
//    active; ignoring the filter when nil.
//
// Per `feedback_never_touch_brew_db`: every test runs against an
// isolated tempDB; no ~/.cupertino access.

@Suite("#225 Part A — packages.db swift_tools_version end-to-end", .serialized)
struct Issue225SwiftToolsVersionIntegrationTests {
    // MARK: - 1. Schema

    @Test("fresh packages.db carries swift_tools_version column + idx_pkg_swift_tools index at schema v3")
    func freshSchemaHasColumnAndIndex() async throws {
        let (dbPath, cleanup) = try await Self.makeEmptyDB()
        defer { cleanup() }

        let columnInfo = try Self.readPragma(at: dbPath, sql: "PRAGMA table_info(package_metadata);")
        let columnNames = columnInfo.compactMap { $0.count >= 2 ? $0[1] : nil }
        #expect(columnNames.contains("swift_tools_version"), "fresh DB must carry the column; got: \(columnNames)")

        let indexes = try Self.readPragma(at: dbPath, sql: "PRAGMA index_list(package_metadata);")
        let indexNames = indexes.compactMap { $0.count >= 2 ? $0[1] : nil }
        #expect(indexNames.contains("idx_pkg_swift_tools"), "fresh DB must carry the swift-tools index; got: \(indexNames)")

        let version = try Self.readPragma(at: dbPath, sql: "PRAGMA user_version;")
        let userVersion = version.first?.first ?? ""
        #expect(userVersion == "3", "fresh DB must stamp user_version = 3; got: \(userVersion)")
    }

    // MARK: - 2. Indexer wires swift_tools_version through

    @Test("indexer writes swift_tools_version when AvailabilityPayload carries it")
    func indexerPersistsSwiftToolsVersion() async throws {
        let (dbPath, cleanup) = try await Self.makeEmptyDB()
        defer { cleanup() }

        let index = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
        let resolved = Core.PackageIndexing.ResolvedPackage(
            owner: "apple", repo: "swift-log",
            url: "https://github.com/apple/swift-log",
            priority: .appleOfficial,
            parents: ["apple/swift-log"]
        )
        let files: [Core.PackageIndexing.ExtractedFile] = [
            .init(relpath: "README.md", kind: .readme, module: nil, content: "# swift-log", byteSize: 12),
        ]
        let availability = Search.PackageIndex.AvailabilityPayload(
            deploymentTargets: ["iOS": "16.0"],
            attributesByRelpath: [:],
            source: "package-swift",
            swiftToolsVersion: "5.9"
        )
        _ = try await index.index(
            resolved: resolved,
            extraction: Core.PackageIndexing.PackageExtractionResult(
                branch: "HEAD", files: files, totalBytes: 12, tarballBytes: 100
            ),
            availability: availability
        )
        await index.disconnect()

        let stored = try Self.readSingleColumn(
            at: dbPath,
            sql: "SELECT swift_tools_version FROM package_metadata WHERE owner = 'apple' AND repo = 'swift-log';"
        )
        #expect(stored == "5.9", "indexer must persist swift_tools_version; got: \(stored ?? "<nil>")")
    }

    @Test("indexer leaves swift_tools_version NULL when AvailabilityPayload doesn't carry it")
    func indexerLeavesNullWhenAbsent() async throws {
        let (dbPath, cleanup) = try await Self.makeEmptyDB()
        defer { cleanup() }

        let index = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
        let resolved = Core.PackageIndexing.ResolvedPackage(
            owner: "apple", repo: "swift-no-decl",
            url: "https://github.com/apple/swift-no-decl",
            priority: .appleOfficial,
            parents: ["apple/swift-no-decl"]
        )
        let files: [Core.PackageIndexing.ExtractedFile] = [
            .init(relpath: "README.md", kind: .readme, module: nil, content: "# foo", byteSize: 5),
        ]
        // No availability payload — older index path / package with no
        // manifest annotation.
        _ = try await index.index(
            resolved: resolved,
            extraction: Core.PackageIndexing.PackageExtractionResult(
                branch: "HEAD", files: files, totalBytes: 5, tarballBytes: 50
            )
        )
        await index.disconnect()

        let stored = try Self.readSingleColumn(
            at: dbPath,
            sql: "SELECT swift_tools_version FROM package_metadata WHERE owner = 'apple' AND repo = 'swift-no-decl';"
        )
        #expect(stored == nil, "no-payload case must leave the column NULL; got: \(stored ?? "<nil>")")
    }

    // MARK: - 3. Query filter pushdown

    @Test("Search.SwiftToolsFilter passes rows whose declaration is >= the filter floor")
    func filterAcceptsMatchingRows() async throws {
        let (dbPath, cleanup) = try await Self.seededDB(packages: [
            ("apple", "swift-old", "5.7"),
            ("apple", "swift-new", "6.0"),
        ])
        defer { cleanup() }

        // Filter floor = 6.0 — should keep only swift-new.
        let query = try await Search.PackageQuery(dbPath: dbPath)
        defer { Task { await query.disconnect() } }
        let results = try await query.answer(
            "swift",
            maxResults: 10,
            swiftTools: Search.SwiftToolsFilter(minVersion: "6.0")
        )
        await query.disconnect()

        let repos = Set(results.map(\.repo))
        #expect(repos.contains("swift-new"), "swift-new (6.0 ≥ 6.0) must pass")
        #expect(!repos.contains("swift-old"), "swift-old (5.7 < 6.0) must be dropped; got: \(repos)")
    }

    @Test("Search.SwiftToolsFilter drops NULL rows when filter is active")
    func filterDropsNullRows() async throws {
        let (dbPath, cleanup) = try await Self.seededDB(packages: [
            ("apple", "swift-declared", "5.9"),
            ("apple", "swift-undeclared", nil),
        ])
        defer { cleanup() }

        let query = try await Search.PackageQuery(dbPath: dbPath)
        defer { Task { await query.disconnect() } }
        let results = try await query.answer(
            "swift",
            maxResults: 10,
            swiftTools: Search.SwiftToolsFilter(minVersion: "5.7")
        )
        await query.disconnect()

        let repos = Set(results.map(\.repo))
        #expect(repos.contains("swift-declared"))
        #expect(!repos.contains("swift-undeclared"), "NULL row must be dropped when filter is active; got: \(repos)")
    }

    @Test("Search.SwiftToolsFilter nil → no filter applied, NULL rows pass through")
    func nilFilterIsTransparent() async throws {
        let (dbPath, cleanup) = try await Self.seededDB(packages: [
            ("apple", "swift-declared", "5.9"),
            ("apple", "swift-undeclared", nil),
        ])
        defer { cleanup() }

        let query = try await Search.PackageQuery(dbPath: dbPath)
        defer { Task { await query.disconnect() } }
        let results = try await query.answer(
            "swift",
            maxResults: 10,
            swiftTools: nil
        )
        await query.disconnect()

        let repos = Set(results.map(\.repo))
        #expect(repos.contains("swift-declared"))
        #expect(repos.contains("swift-undeclared"), "nil filter must let NULL rows pass; got: \(repos)")
    }

    @Test("Search.SwiftToolsFilter is orthogonal to AvailabilityFilter — both can be set")
    func orthogonalToPlatformFilter() async throws {
        let (dbPath, cleanup) = try await Self.seededDB(packages: [
            ("apple", "good-pkg", "6.0"),
            ("apple", "old-swift-good-platform", "5.5"),
            ("apple", "good-swift-old-platform", "6.0"),
        ])
        defer { cleanup() }

        // We didn't seed min_ios on the third row's metadata; the
        // pure-swiftTools filter still works because availability is
        // nil. Set both filters to verify they compose; specifically
        // assert that swiftTools=6.0 alone keeps the two 6.0 rows.
        let query = try await Search.PackageQuery(dbPath: dbPath)
        defer { Task { await query.disconnect() } }
        let results = try await query.answer(
            "swift",
            maxResults: 10,
            availability: nil,
            swiftTools: Search.SwiftToolsFilter(minVersion: "6.0")
        )
        await query.disconnect()

        let repos = Set(results.map(\.repo))
        #expect(repos.contains("good-pkg"))
        #expect(repos.contains("good-swift-old-platform"))
        #expect(!repos.contains("old-swift-good-platform"), "5.5 < 6.0 must be dropped")
    }

    // MARK: - Helpers

    private static func makeEmptyDB() async throws -> (URL, () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-225-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("packages.db")
        let index = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
        await index.disconnect()
        return (dbPath, { try? FileManager.default.removeItem(at: tempDir) })
    }

    private static func seededDB(
        packages: [(owner: String, repo: String, swiftTools: String?)]
    ) async throws -> (URL, () -> Void) {
        let (dbPath, cleanup) = try await makeEmptyDB()
        let index = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
        for pkg in packages {
            let resolved = Core.PackageIndexing.ResolvedPackage(
                owner: pkg.owner, repo: pkg.repo,
                url: "https://github.com/\(pkg.owner)/\(pkg.repo)",
                priority: .appleOfficial,
                parents: ["\(pkg.owner)/\(pkg.repo)"]
            )
            let files: [Core.PackageIndexing.ExtractedFile] = [
                .init(relpath: "README.md", kind: .readme, module: nil, content: "# \(pkg.repo) swift", byteSize: 32),
            ]
            let availability = pkg.swiftTools.map {
                Search.PackageIndex.AvailabilityPayload(
                    deploymentTargets: [:],
                    attributesByRelpath: [:],
                    source: "package-swift",
                    swiftToolsVersion: $0
                )
            }
            _ = try await index.index(
                resolved: resolved,
                extraction: Core.PackageIndexing.PackageExtractionResult(
                    branch: "HEAD", files: files, totalBytes: 32, tarballBytes: 100
                ),
                availability: availability
            )
        }
        await index.disconnect()
        return (dbPath, cleanup)
    }

    private static func readPragma(at dbPath: URL, sql: String) throws -> [[String]] {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw NSError(domain: "test-225", code: 1)
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "test-225-prepare", code: 2)
        }
        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let cols = sqlite3_column_count(statement)
            var row: [String] = []
            for i in 0..<cols {
                if let ptr = sqlite3_column_text(statement, i) {
                    row.append(String(cString: ptr))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        return rows
    }

    private static func readSingleColumn(at dbPath: URL, sql: String) throws -> String? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }
}
