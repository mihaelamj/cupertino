import ASTIndexer
import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #409 Layer 1 — `is_public` is now tautologically true for apple-docs

//
// Pre-fix, `is_public` was set from a literal `public` modifier on the
// declaration. Apple's doc code snippets never write `public` explicitly
// (it's redundant; everything documented IS public), so the column read
// `1` for ~0% of rows (24 of 168,259 in the v1.0.3 snapshot). The
// column carried no useful signal for our corpus.
//
// Post-fix: for apple-docs-sourced pages, `is_public` is always `1`.
// Any future internal sample-code blocks (where `private` / `internal`
// actually appears in source) fall through to the original literal-
// keyword interpretation so a future "exclude internal helpers" query
// has the signal it needs.

@Suite("#409 Layer 1 — is_public repurpose for apple-docs", .serialized)
struct Issue409IsPublicRepurposeTests {
    private func makeIndex() async throws -> (Search.Index, URL) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-409-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording())
        return (index, tempDB)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func readIsPublic(dbPath: URL, docURI: String, symbolName: String) throws -> Bool {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw NSError(domain: "test", code: 1)
        }
        let sql = "SELECT is_public FROM doc_symbols WHERE doc_uri = ? AND name = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test", code: 2)
        }
        sqlite3_bind_text(stmt, 1, (docURI as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (symbolName as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "row not found for \(docURI) / \(symbolName)"])
        }
        return sqlite3_column_int(stmt, 0) != 0
    }

    @Test("apple-docs-sourced symbol gets is_public=1 even when extractor saw no `public` keyword")
    func appleDocsTautologicallyPublic() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // Pre-#409: symbol.isPublic = false → is_public column = 0.
        // Post-#409: docURI is apple-docs:// → is_public column = 1.
        let symbol = ASTIndexer.Symbol(
            name: "fetchItems",
            kind: .function,
            line: 1,
            column: 1,
            signature: "func fetchItems() async throws -> [Item]",
            isAsync: true,
            isThrows: true,
            isPublic: false, // critical: extractor saw no modifier
            isStatic: false
        )
        let docURI = "apple-docs://swiftui/view/fetchitems"

        // First write the parent docs_metadata + docs_fts row so the FTS
        // foreign-key constraint in indexDocSymbolFTS is satisfied.
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: docURI,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "swiftui",
            title: "fetchItems",
            content: "Stub",
            filePath: "/tmp/stub.json",
            contentHash: "hash",
            lastCrawled: Date(),
            sourceType: "apple"
        ))

        try await index.indexDocSymbols(docUri: docURI, symbols: [symbol])
        await index.disconnect()

        let isPublic = try readIsPublic(dbPath: dbPath, docURI: docURI, symbolName: "fetchItems")
        #expect(isPublic, "apple-docs symbol with extractor isPublic=false should still be flagged is_public=1 post-#409")
    }

    @Test("Non-apple-docs sources still honour the literal-keyword extractor (no false positives)")
    func nonAppleDocsHonoursExtractor() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // A future sample-code or package source where `private` actually
        // appears in the source. The repurpose must not override that —
        // otherwise downstream "exclude internal helpers" queries lose
        // the signal entirely.
        let symbol = ASTIndexer.Symbol(
            name: "internalHelper",
            kind: .function,
            line: 1,
            column: 1,
            signature: "private func internalHelper() {}",
            isAsync: false,
            isThrows: false,
            isPublic: false,
            isStatic: false
        )
        let docURI = "samples://my-sample-project/internal-helper"

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: docURI,
            source: Shared.Constants.SourcePrefix.samples,
            framework: "samples",
            title: "internalHelper",
            content: "Stub",
            filePath: "/tmp/stub.json",
            contentHash: "hash",
            lastCrawled: Date(),
            sourceType: "samples"
        ))

        try await index.indexDocSymbols(docUri: docURI, symbols: [symbol])
        await index.disconnect()

        let isPublic = try readIsPublic(dbPath: dbPath, docURI: docURI, symbolName: "internalHelper")
        #expect(!isPublic, "non-apple-docs symbol with extractor isPublic=false should stay is_public=0")
    }

    @Test("apple-docs symbol that the extractor DID see as public stays is_public=1 (no regression)")
    func appleDocsExplicitlyPublic() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        let symbol = ASTIndexer.Symbol(
            name: "rarelySeenPublicKeyword",
            kind: .function,
            line: 1,
            column: 1,
            signature: "public func rarelySeenPublicKeyword() {}",
            isAsync: false,
            isThrows: false,
            isPublic: true, // the 24-of-168k case
            isStatic: false
        )
        let docURI = "apple-docs://framework-design-article/rarely-seen-public-keyword"

        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: docURI,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "framework-design-article",
            title: "rarelySeenPublicKeyword",
            content: "Stub",
            filePath: "/tmp/stub.json",
            contentHash: "hash",
            lastCrawled: Date(),
            sourceType: "apple"
        ))

        try await index.indexDocSymbols(docUri: docURI, symbols: [symbol])
        await index.disconnect()

        let isPublic = try readIsPublic(dbPath: dbPath, docURI: docURI, symbolName: "rarelySeenPublicKeyword")
        #expect(isPublic)
    }
}
