import Core
import Foundation
import Logging
@testable import Search
import Shared
import SQLite3
import Testing

// End-to-end test that a real `Search.IndexBuilder` run on a fixture
// directory of structured JSON docs produces populated `doc_symbols` rows,
// a `docs_metadata.symbols` blob, AND a searchable `docs_fts.symbols`
// column (#192 section D). Guards the wiring in
// `SearchIndexBuilder.indexAppleDocsFromDirectory` that the unit tests on
// `extractCodeExampleSymbols` cannot exercise.

private enum BuilderTestError: Error {
    case openFailed(String)
    case prepareFailed(String)
}

private func readSymbolsBlob(at dbPath: URL, uri: String) throws -> String? {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw BuilderTestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, "SELECT symbols FROM docs_metadata WHERE uri = ?;", -1, &stmt, nil) == SQLITE_OK else {
        throw BuilderTestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
    if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
    return String(cString: sqlite3_column_text(stmt, 0))
}

private func ftsSymbolsMatches(at dbPath: URL, uri: String) throws -> Bool {
    // Query docs_fts directly — if the builder wired the AST pass, the
    // `symbols` FTS column will match tokens extracted from the code block.
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw BuilderTestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    let sql = "SELECT uri FROM docs_fts WHERE symbols MATCH ? AND uri = ?;"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw BuilderTestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    sqlite3_bind_text(stmt, 1, ("SampleModel" as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 2, (uri as NSString).utf8String, -1, nil)
    return sqlite3_step(stmt) == SQLITE_ROW
}

private func countDocSymbolRows(at dbPath: URL, uri: String) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw BuilderTestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM doc_symbols WHERE doc_uri = ?;", -1, &stmt, nil) == SQLITE_OK else {
        throw BuilderTestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int(stmt, 0))
}

/// Build a `StructuredDocumentationPage` JSON fixture whose declaration and
/// code block declare DIFFERENT symbols, so the integration test can verify
/// both sources flow into the blob (covers #192 D Fix B + the original
/// code-example pass at the same time).
private func writeFixtureDoc(framework: String, name: String, into directory: URL) throws -> URL {
    let frameworkDir = directory.appendingPathComponent(framework)
    try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)

    let page = StructuredDocumentationPage(
        url: URL(string: "https://developer.apple.com/documentation/\(framework)/\(name)")!,
        title: "Sample page",
        kind: .protocol,
        source: .appleJSON,
        abstract: "An example doc with both a declaration and a Swift code block.",
        declaration: StructuredDocumentationPage.Declaration(code: "public protocol DeclaredProtocol {}"),
        overview: "Overview text.",
        sections: [],
        codeExamples: [
            .init(
                code: "import SwiftUI\n\nstruct SampleModel {\n    var name: String\n}\n",
                language: "swift",
                caption: nil
            ),
        ],
        language: "swift",
        crawledAt: Date(),
        contentHash: "test-hash"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(page)

    let fileURL = frameworkDir.appendingPathComponent("\(name).json")
    try data.write(to: fileURL)
    return fileURL
}

@Suite("Search.IndexBuilder wires AST extraction (#192 D)", .serialized)
struct IndexBuilderSymbolsIntegrationTests {
    @Test("buildIndex populates doc_symbols + docs_fts.symbols from fixture docs")
    func buildIndexPopulatesSymbols() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-builder-symbols-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let docsDir = tempRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        _ = try writeFixtureDoc(framework: "swiftui", name: "sample", into: docsDir)

        let dbPath = tempRoot.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath)
        let builder = Search.IndexBuilder(
            searchIndex: index,
            metadata: nil,
            docsDirectory: docsDir,
            indexSampleCode: false
        )

        try await builder.buildIndex(clearExisting: true)
        await index.disconnect()

        let uri = "apple-docs://swiftui/sample"
        let symbolRows = try countDocSymbolRows(at: dbPath, uri: uri)
        #expect(symbolRows >= 2, "doc_symbols should hold both the declaration AND code-block symbols")

        let blob = try #require(try readSymbolsBlob(at: dbPath, uri: uri))
        #expect(blob.contains("DeclaredProtocol"), "blob must include the declaration-derived symbol (Fix B)")
        #expect(blob.contains("SampleModel"), "blob must include the code-block-derived symbol")

        let ftsHit = try ftsSymbolsMatches(at: dbPath, uri: uri)
        #expect(ftsHit, "docs_fts.symbols should match the extracted symbol via FTS5 MATCH")
    }
}
