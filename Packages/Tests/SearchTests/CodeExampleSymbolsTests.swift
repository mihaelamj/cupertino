import Foundation
@testable import Search
import Shared
import SQLite3
import Testing

// AST extraction over stored `doc_code_examples` (#192 section D).
//
// Exercises `Search.Index.extractCodeExampleSymbols` end-to-end against a
// real temp DB so the symbol/import inserts and the denormalised
// `docs_metadata.symbols` blob are all guarded.

private func makeTempDB() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("code-example-symbols-\(UUID().uuidString).db")
}

private enum SymbolsTestError: Error {
    case openFailed(String)
    case prepareFailed(String)
}

private func readSymbolsBlob(at dbPath: URL, uri: String) throws -> String? {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw SymbolsTestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, "SELECT symbols FROM docs_metadata WHERE uri = ?;", -1, &stmt, nil) == SQLITE_OK else {
        throw SymbolsTestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
    if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
    return String(cString: sqlite3_column_text(stmt, 0))
}

private func countSymbolRows(at dbPath: URL, uri: String) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw SymbolsTestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM doc_symbols WHERE doc_uri = ?;", -1, &stmt, nil) == SQLITE_OK else {
        throw SymbolsTestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int(stmt, 0))
}

private func countImportRows(at dbPath: URL, uri: String) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw SymbolsTestError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM doc_imports WHERE doc_uri = ?;", -1, &stmt, nil) == SQLITE_OK else {
        throw SymbolsTestError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int(stmt, 0))
}

private func seedDoc(index: Search.Index, uri: String) async throws {
    try await index.indexDocument(
        uri: uri,
        source: "apple-docs",
        framework: "swiftui",
        title: "Test doc",
        content: "placeholder body",
        filePath: "/tmp/x",
        contentHash: "h",
        lastCrawled: Date()
    )
}

@Suite("Search.Index.extractCodeExampleSymbols (#192 D)")
struct CodeExampleSymbolsTests {
    @Test("Swift code block: symbols land in doc_symbols, names in docs_metadata.symbols")
    func swiftBlockPopulatesAll() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let uri = "apple-docs://swiftui/view"
        let index = try await Search.Index(dbPath: dbPath)
        try await seedDoc(index: index, uri: uri)

        let examples: [(code: String, language: String)] = [
            (code: """
            import SwiftUI

            struct ContentView: View {
                var body: some View { Text("Hello") }
            }
            """, language: "swift"),
        ]
        try await index.extractCodeExampleSymbols(docUri: uri, codeExamples: examples)
        await index.disconnect()

        #expect(try countSymbolRows(at: dbPath, uri: uri) > 0)
        #expect(try countImportRows(at: dbPath, uri: uri) > 0)
        let blob = try #require(try readSymbolsBlob(at: dbPath, uri: uri))
        #expect(blob.contains("ContentView"))
    }

    @Test("Symbols blob is tab-separated, sorted, and deduplicated")
    func blobIsSortedAndUnique() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let uri = "apple-docs://swiftui/zebra"
        let index = try await Search.Index(dbPath: dbPath)
        try await seedDoc(index: index, uri: uri)

        // Two blocks. `Beta` appears in both — must dedupe. `Alpha` and `Zulu`
        // appear once each. Sorted order must be Alpha, Beta, Zulu.
        let examples: [(code: String, language: String)] = [
            (code: "struct Beta {}\nstruct Zulu {}\n", language: "swift"),
            (code: "struct Alpha {}\nstruct Beta {}\n", language: "swift"),
        ]
        try await index.extractCodeExampleSymbols(docUri: uri, codeExamples: examples)
        await index.disconnect()

        let blob = try #require(try readSymbolsBlob(at: dbPath, uri: uri))
        let tokens = blob.split(separator: "\t").map(String.init)
        #expect(tokens == tokens.sorted())
        #expect(Set(tokens).count == tokens.count)
        #expect(tokens.contains("Alpha"))
        #expect(tokens.contains("Beta"))
        #expect(tokens.contains("Zulu"))
    }

    @Test("Non-Swift language blocks are ignored")
    func nonSwiftBlocksIgnored() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let uri = "apple-docs://swiftui/only-shell"
        let index = try await Search.Index(dbPath: dbPath)
        try await seedDoc(index: index, uri: uri)

        let examples: [(code: String, language: String)] = [
            (code: "echo hello", language: "shell"),
            (code: "<xml/>", language: "xml"),
            (code: "print('py')", language: "python"),
        ]
        try await index.extractCodeExampleSymbols(docUri: uri, codeExamples: examples)
        await index.disconnect()

        #expect(try countSymbolRows(at: dbPath, uri: uri) == 0)
        #expect(try readSymbolsBlob(at: dbPath, uri: uri) == nil)
    }

    @Test("Empty code examples list is a no-op")
    func emptyListIsNoop() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let uri = "apple-docs://swiftui/empty"
        let index = try await Search.Index(dbPath: dbPath)
        try await seedDoc(index: index, uri: uri)

        try await index.extractCodeExampleSymbols(docUri: uri, codeExamples: [])
        await index.disconnect()

        #expect(try countSymbolRows(at: dbPath, uri: uri) == 0)
        #expect(try countImportRows(at: dbPath, uri: uri) == 0)
        #expect(try readSymbolsBlob(at: dbPath, uri: uri) == nil)
    }

    @Test("Declaration symbols (no code blocks) populate the symbols blob (#192 D Fix B)")
    func declarationOnlyPopulatesBlob() async throws {
        // Symbol pages typically have a `declaration.code` and zero code
        // examples. Before Fix B, the blob stayed NULL on these pages —
        // bm25 lost the symbol-name boost. After: declaration AST symbols
        // flow into doc_symbols and into the blob via recomputeSymbolsBlob.
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let uri = "apple-docs://swiftui/observable"
        let index = try await Search.Index(dbPath: dbPath)

        let page = try StructuredDocumentationPage(
            url: #require(URL(string: "https://developer.apple.com/documentation/swiftui/observable")),
            title: "Observable",
            kind: .protocol,
            source: .appleJSON,
            abstract: "An object that announces changes to its properties.",
            declaration: StructuredDocumentationPage.Declaration(code: "@MainActor public protocol Observable {}"),
            language: "swift",
            crawledAt: Date(),
            contentHash: "test"
        )

        try await index.indexStructuredDocument(
            uri: uri,
            source: "apple-docs",
            framework: "swiftui",
            page: page,
            jsonData: "{}"
        )
        await index.disconnect()

        let blob = try #require(try readSymbolsBlob(at: dbPath, uri: uri))
        #expect(blob.contains("Observable"), "declaration-derived symbol must land in the blob")
        #expect(try countSymbolRows(at: dbPath, uri: uri) > 0)
    }

    @Test("Blocks without recognised symbols do not touch the blob")
    func emptyExtractionDoesNotWriteBlob() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let uri = "apple-docs://swiftui/noop-swift"
        let index = try await Search.Index(dbPath: dbPath)
        try await seedDoc(index: index, uri: uri)

        // Swift block that has no declarations — only an expression statement.
        let examples: [(code: String, language: String)] = [
            (code: "1 + 1\n", language: "swift"),
        ]
        try await index.extractCodeExampleSymbols(docUri: uri, codeExamples: examples)
        await index.disconnect()

        #expect(try readSymbolsBlob(at: dbPath, uri: uri) == nil)
    }
}
