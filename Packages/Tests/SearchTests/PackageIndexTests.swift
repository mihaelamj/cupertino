// swiftlint:disable identifier_name
@testable import Core
import Foundation
@testable import Search
import Shared
import SQLite3
import Testing

// MARK: - symbolTokens / splitIdentifier

@Test("splitIdentifier: camelCase → space-separated")
func splitCamel() {
    #expect(Search.PackageIndex.splitIdentifier("makeHTTPRequest") == "make HTTP Request")
}

@Test("splitIdentifier: ALL_CAPS + snake_case")
func splitSnake() {
    #expect(Search.PackageIndex.splitIdentifier("URL_SESSION_SHARED") == "URL SESSION SHARED")
}

@Test("splitIdentifier: HTTPServer (consecutive caps) → HTTP Server")
func splitConsecutiveCaps() {
    #expect(Search.PackageIndex.splitIdentifier("HTTPServer") == "HTTP Server")
}

@Test("splitIdentifier: simple lowercase untouched")
func splitSimpleLower() {
    #expect(Search.PackageIndex.splitIdentifier("vapor") == "vapor")
}

@Test("symbolTokens: contains both original and split forms")
func symbolTokensBothForms() {
    let out = Search.PackageIndex.symbolTokens(from: "let x = makeHTTPRequest(url)")
    #expect(out.contains("makeHTTPRequest"))
    #expect(out.contains("make HTTP Request"))
    #expect(out.contains("url"))
}

@Test("extractTitle: markdown uses first H1")
func extractTitleMarkdownH1() {
    let md = "# My Package\n\nSome text."
    #expect(Search.PackageIndex.extractTitle(relpath: "README.md", content: md) == "My Package")
}

@Test("extractTitle: markdown without H1 falls back to filename")
func extractTitleMarkdownNoH1() {
    let md = "Just text, no heading."
    #expect(Search.PackageIndex.extractTitle(relpath: "README.md", content: md) == "README.md")
}

@Test("extractTitle: non-markdown uses filename")
func extractTitleNonMarkdown() {
    #expect(Search.PackageIndex.extractTitle(relpath: "Sources/Foo/Foo.swift", content: "// blah") == "Foo.swift")
}

// MARK: - PackageIndex SQL round-trip

// MARK: - FTS search against a populated temp DB

@Test("PackageIndex: content column matches on words")
func packageIndexSearchesContent() async throws {
    let (dbPath, cleanup) = try await seedTempIndex()
    defer { cleanup() }

    // Open directly (bypasses the actor so we can run a raw SELECT).
    let rows = try runFTSQuery(
        dbPath: dbPath,
        sql: "SELECT owner, repo, relpath FROM package_files_fts WHERE content MATCH 'logger' ORDER BY bm25(package_files_fts)"
    )
    #expect(rows.count >= 1)
    #expect(rows.contains { $0[2] == "Sources/Logging/Logger.swift" })
}

@Test("PackageIndex: symbols column finds camelCase tokens")
func packageIndexSymbolsColumnCamelCase() async throws {
    let (dbPath, cleanup) = try await seedTempIndex()
    defer { cleanup() }

    // Query for a WORD that's only present inside a camelCase identifier.
    // The symbols column contains a case-split form so this should match.
    let rows = try runFTSQuery(
        dbPath: dbPath,
        sql: "SELECT relpath FROM package_files_fts WHERE symbols MATCH 'level'"
    )
    #expect(!rows.isEmpty)
}

@Test("PackageIndex: kind filter restricts results")
func packageIndexKindFilter() async throws {
    let (dbPath, cleanup) = try await seedTempIndex()
    defer { cleanup() }

    let readmeHits = try runFTSQuery(
        dbPath: dbPath,
        sql: "SELECT relpath FROM package_files_fts WHERE content MATCH 'logging' AND kind = 'readme'"
    )
    let sourceHits = try runFTSQuery(
        dbPath: dbPath,
        sql: "SELECT relpath FROM package_files_fts WHERE content MATCH 'logging' AND kind = 'source'"
    )
    #expect(readmeHits.allSatisfy { $0[0].hasSuffix("README.md") })
    #expect(sourceHits.allSatisfy { $0[0].hasSuffix(".swift") })
}

// MARK: - Helpers for FTS tests

private func seedTempIndex() async throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-pkgidx-ftstest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbPath = tempDir.appendingPathComponent("packages.db")

    let index = try await Search.PackageIndex(dbPath: dbPath)
    let resolved = Core.ResolvedPackage(
        owner: "apple", repo: "swift-log",
        url: "https://github.com/apple/swift-log",
        priority: .appleOfficial,
        parents: ["apple/swift-log"]
    )
    let files: [Core.ExtractedFile] = [
        .init(
            relpath: "README.md",
            kind: .readme,
            module: nil,
            content: "# swift-log\n\nUnified logging API for Swift.",
            byteSize: 50
        ),
        .init(
            relpath: "Sources/Logging/Logger.swift",
            kind: .source,
            module: "Logging",
            content: "public struct Logger { public var logLevel = LogLevel.info; public let label: String }",
            byteSize: 100
        ),
    ]
    _ = try await index.index(
        resolved: resolved,
        extraction: Core.PackageArchiveExtractor.Result(
            branch: "HEAD", files: files, totalBytes: 150, tarballBytes: 1000
        )
    )
    await index.disconnect()
    return (dbPath, { try? FileManager.default.removeItem(at: tempDir) })
}

private func runFTSQuery(dbPath: URL, sql: String) throws -> [[String]] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw PackageIndexTestError.sqliteOpen
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw PackageIndexTestError.sqlitePrepare(String(cString: sqlite3_errmsg(db)))
    }
    var rows: [[String]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let colCount = sqlite3_column_count(statement)
        var row: [String] = []
        for i in 0..<colCount {
            if let cstr = sqlite3_column_text(statement, i) {
                row.append(String(cString: cstr))
            } else {
                row.append("")
            }
        }
        rows.append(row)
    }
    return rows
}

private enum PackageIndexTestError: Error {
    case sqliteOpen
    case sqlitePrepare(String)
}

@Test("PackageIndex: index + summary + dedupe round-trip")
func packageIndexRoundTrip() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-pkgidx-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let dbPath = tempDir.appendingPathComponent("packages.db")

    let index = try await Search.PackageIndex(dbPath: dbPath)
    defer { Task { await index.disconnect() } }

    let resolved = Core.ResolvedPackage(
        owner: "apple",
        repo: "swift-log",
        url: "https://github.com/apple/swift-log",
        priority: .appleOfficial,
        parents: ["apple/swift-log"]
    )
    let files: [Core.ExtractedFile] = [
        .init(
            relpath: "README.md",
            kind: .readme,
            module: nil,
            content: "# swift-log\n\nLogging for Swift.",
            byteSize: 40
        ),
        .init(
            relpath: "Sources/Logging/Logger.swift",
            kind: .source,
            module: "Logging",
            content: "public struct Logger { public var logLevel: Level = .info }",
            byteSize: 60
        ),
    ]
    let extraction = Core.PackageArchiveExtractor.Result(
        branch: "HEAD",
        files: files,
        totalBytes: 100,
        tarballBytes: 9000
    )

    // First index
    let r1 = try await index.index(resolved: resolved, extraction: extraction)
    #expect(r1.filesIndexed == 2)
    let s1 = try await index.summary()
    #expect(s1.packageCount == 1)
    #expect(s1.fileCount == 2)

    // Re-index same package — should replace, not duplicate
    let r2 = try await index.index(resolved: resolved, extraction: extraction)
    #expect(r2.filesIndexed == 2)
    let s2 = try await index.summary()
    #expect(s2.packageCount == 1)
    #expect(s2.fileCount == 2)
}
