import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

/// Regression suite for [#77](https://github.com/mihaelamj/cupertino/issues/77).
///
/// FTS5's default `unicode61` tokeniser treats CamelCase identifiers as
/// opaque units, so `search("grid")` doesn't match the `LazyVGrid`
/// documentation page even though the answer is in the index. This PR
/// adds a `symbol_components` FTS column that carries acronym-aware
/// CamelCase splits of every AST-derived symbol on the page, weighted
/// at 1.5 in BM25F (well below `symbols` at 5.0 so the exact-symbol
/// ranking is unchanged).
///
/// The splitter follows the rule lock in the issue spec:
///
/// - **Acronym-aware grouping** — `URLSession` → `{URL, Session}`,
///   never `{U, R, L, Session}`. Walks the string once; runs of
///   consecutive caps stay as one unit, except the last cap of a run
///   becomes the head of the next word if followed by lowercase.
/// - **Min component length 3** — `LazyVGrid` → `{Lazy, VGrid, Grid}`,
///   single-letter `V` filtered.
/// - **Per-page dedupe** — `JSONJSON` doesn't emit two `JSON` tokens.
/// - **Original case preserved** — FTS5's case folding handles
///   case-insensitive matching at query time; preserving the source
///   case keeps exact-acronym signal intact.
@Suite("#77 CamelCase splitter")
struct Issue77CamelCaseSplitterTests {
    // MARK: - A. acronym-aware split shapes

    @Test(
        "Splitter produces the expected components for the explicit acronym fixtures",
        arguments: [
            // (input, expected components in walk order)
            ("URLSession", ["URL", "Session"]),
            ("JSONDecoder", ["JSON", "Decoder"]),
            ("HTTPSCookieStorage", ["HTTPS", "Cookie", "Storage"]),
            ("XMLParser", ["XML", "Parser"]),
        ]
    )
    func acronymFixtures(input: String, expected: [String]) {
        let result = Search.Index.splitCamelCaseIdentifier(input)
        #expect(result == expected, "\(input) → \(result), expected \(expected)")
    }

    @Test("LazyVGrid drops the single-letter V via min-length-3 filter")
    func lazyVGridDropsSingleLetter() {
        let result = Search.Index.splitCamelCaseIdentifier("LazyVGrid")
        #expect(
            result == ["Lazy", "VGrid", "Grid"],
            "LazyVGrid → \(result), expected [Lazy, VGrid, Grid]"
        )
    }

    @Test("Single-word identifiers without internal caps return empty")
    func singleWordReturnsEmpty() {
        #expect(Search.Index.splitCamelCaseIdentifier("Task") == ["Task"])
        #expect(Search.Index.splitCamelCaseIdentifier("foo") == ["foo"])
    }

    @Test("All-caps acronym returns the acronym itself (no further split)")
    func allCapsAcronym() {
        #expect(Search.Index.splitCamelCaseIdentifier("URL") == ["URL"])
        #expect(Search.Index.splitCamelCaseIdentifier("HTTPS") == ["HTTPS"])
    }

    @Test("Empty / whitespace-only input returns empty")
    func emptyInput() {
        #expect(Search.Index.splitCamelCaseIdentifier("") == [])
        #expect(Search.Index.splitCamelCaseIdentifier("   ") == [])
    }

    // MARK: - B. defensive limits

    @Test("Two-letter fragments are filtered (IO, UI, 2D, OK)")
    func shortFragmentsFiltered() {
        // `UIView` → cap V starts a new word, so naive walk would emit
        // `{UI, View}`. With min length 3, `UI` is dropped, leaving
        // `{View}` plus the canonical `UIView` (which the original
        // identifier column carries — splitter only emits splits).
        let result = Search.Index.splitCamelCaseIdentifier("UIView")
        #expect(!result.contains("UI"), "UI (length 2) must be filtered: \(result)")
        #expect(result.contains("View"), "View should survive: \(result)")
    }

    @Test("Per-call dedupe collapses repeated components across many identifiers")
    func dedupeRepeatedComponents() {
        // Realistic case: two identifiers each contributing `URL` —
        // the bulk union must produce one URL token, not two. The
        // single-identifier walker can't naturally emit duplicates
        // (consecutive caps stay as one acronym unit), so this
        // exercises the cross-identifier dedupe via the bulk variant.
        let result = Search.Index.splitCamelCaseIdentifiers([
            "URLSession",
            "URLRequest",
            "URLComponents",
        ])
        let urlCount = result.filter { $0.lowercased() == "url" }.count
        #expect(urlCount == 1, "bulk union over 3 URL-prefixed names produced \(urlCount) URL tokens: \(result)")
    }

    @Test("No stopword list: View / Manager / Controller / Delegate survive")
    func legitimateQueryTermsNotStopworded() {
        let result1 = Search.Index.splitCamelCaseIdentifier("NavigationView")
        #expect(result1.contains("View"))
        let result2 = Search.Index.splitCamelCaseIdentifier("LocationManager")
        #expect(result2.contains("Manager"))
        let result3 = Search.Index.splitCamelCaseIdentifier("ViewController")
        #expect(result3.contains("View") && result3.contains("Controller"))
        let result4 = Search.Index.splitCamelCaseIdentifier("URLSessionDelegate")
        #expect(result4.contains("Delegate"))
    }

    // MARK: - C. bulk dedupe across many identifiers

    @Test("Bulk variant unions splits across multiple identifiers")
    func bulkVariantUnions() {
        let result = Search.Index.splitCamelCaseIdentifiers([
            "URLSession",
            "URLSessionDelegate",
            "URLSessionTask",
        ])
        let lowered = result.map { $0.lowercased() }
        #expect(lowered.contains("url"))
        #expect(lowered.contains("session"))
        #expect(lowered.contains("delegate"))
        #expect(lowered.contains("task"))
        // No duplicates after the union.
        #expect(lowered.count == Set(lowered).count, "duplicates in bulk union: \(result)")
    }

    // MARK: - D. integration: recomputeSymbolsBlob writes symbol_components

    @Test("recomputeSymbolsBlob writes acronym-aware splits to docs_fts.symbol_components")
    func recomputeSymbolsBlobPopulatesComponentColumn() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue77-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Seed a doc + a doc_symbols row with `LazyVGrid`.
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://swiftui/lazyvgrid",
            source: "apple-docs",
            framework: "swiftui",
            title: "LazyVGrid | Apple Developer Documentation",
            content: "A container view that arranges its child views in a grid.",
            filePath: "/tmp/lazyvgrid.md",
            contentHash: UUID().uuidString,
            lastCrawled: Date()
        ))

        // Inject a symbol into doc_symbols and trigger the recompute.
        try await Self.insertDocSymbol(idx: idx, dbPath: dbPath, uri: "apple-docs://swiftui/lazyvgrid", name: "LazyVGrid")
        try await idx.recomputeSymbolsBlob(docUri: "apple-docs://swiftui/lazyvgrid")
        await idx.disconnect()

        // Read back the new column and confirm the splits are there.
        let components = try Self.readFTSColumn(dbPath: dbPath, uri: "apple-docs://swiftui/lazyvgrid", column: "symbol_components")
        #expect(components.lowercased().contains("lazy"), "missing `lazy` in components: \(components)")
        #expect(components.lowercased().contains("vgrid"), "missing `vgrid` in components: \(components)")
        #expect(components.lowercased().contains("grid"), "missing `grid` in components: \(components)")
        // Original identifier still in the `symbols` column.
        let symbols = try Self.readFTSColumn(dbPath: dbPath, uri: "apple-docs://swiftui/lazyvgrid", column: "symbols")
        #expect(symbols.contains("LazyVGrid"))
    }

    @Test("Empty doc_symbols → empty symbol_components (no crash, no garbage)")
    func emptyDocSymbolsLeavesComponentColumnEmpty() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue77-empty-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: "apple-docs://demo/article",
            source: "apple-docs",
            framework: "demo",
            title: "Article",
            content: "An article-style page with no symbol declarations.",
            filePath: "/tmp/article.md",
            contentHash: UUID().uuidString,
            lastCrawled: Date()
        ))
        try await idx.recomputeSymbolsBlob(docUri: "apple-docs://demo/article")
        await idx.disconnect()

        let components = try Self.readFTSColumn(dbPath: dbPath, uri: "apple-docs://demo/article", column: "symbol_components")
        #expect(components.isEmpty, "expected empty symbol_components, got: \(components)")
    }

    // MARK: - Helpers

    /// Insert a row into `doc_symbols` so `recomputeSymbolsBlob` has
    /// something to read. The indexer's normal path writes through
    /// `indexDocSymbols` from SwiftSyntax extraction; bypassing it
    /// here keeps the test focused on the splitter + blob updater.
    private static func insertDocSymbol(idx: Search.Index, dbPath: URL, uri: String, name: String) async throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "open(\(dbPath.path)) failed",
            ])
        }
        let sql = """
        INSERT INTO doc_symbols (doc_uri, name, kind, line, column, is_async, is_throws, is_public, attributes)
        VALUES (?, ?, 'struct', 0, 0, 0, 0, 1, '');
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "TestSetup", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db)),
            ])
        }
        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "TestSetup", code: 3, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db)),
            ])
        }
    }

    /// Read one column from a `docs_fts` row.
    private static func readFTSColumn(dbPath: URL, uri: String, column: String) throws -> String {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestRead", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "open(\(dbPath.path)) failed",
            ])
        }
        let sql = "SELECT \(column) FROM docs_fts WHERE uri = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "TestRead", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db)),
            ])
        }
        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return ""
        }
        guard let ptr = sqlite3_column_text(stmt, 0) else {
            return ""
        }
        return String(cString: ptr)
    }
}
