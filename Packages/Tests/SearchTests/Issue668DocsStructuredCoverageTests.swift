import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #668 — docs_structured coverage gap for HIG / SwiftEvolution / AppleArchive

//
// Pre-fix the 3 markdown-source strategies (HIGStrategy, SwiftEvolutionStrategy,
// AppleArchiveStrategy) called `Search.Index.indexDocument` (FTS-only path)
// instead of `Search.Index.indexStructuredDocument` (FTS + docs_structured).
// `cupertino doctor --kind-coverage` on the v1.2.0 bundle therefore reported
// `apple-archive` / `hig` / `swift-evolution` at 100% `(missing)` rate —
// every search-quality fix that depends on `s.kind` (the #177 rerank tier,
// the #616 kind-aware tiebreak, the #630 canonical-prepend filter) was a
// no-op for these sources.
//
// Post-fix each strategy builds a minimal `StructuredDocumentationPage` with
// `kind: .article` + `source: .custom` via the new shared
// `Search.StrategyHelpers.makeArticleStructuredPage(...)` helper and calls
// `indexStructuredDocument`. `docs_structured.(missing)` rate drops to 0 %
// for all three sources.

@Suite("#668 — markdown-source strategies write docs_structured rows", .serialized)
struct Issue668DocsStructuredCoverageTests {
    // MARK: - Helpers

    private func makeIndex() async throws -> (Search.Index, URL) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-668-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording())
        return (index, tempDB)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Read `(uri, kind)` from `docs_structured` for the given URI by
    /// re-opening the on-disk SQLite file with a fresh handle (the test's
    /// `Search.Index` actor holds an exclusive writer that the test can't
    /// reach into safely from outside). Caller must disconnect the index
    /// before calling this so the file is flushed. Returns nil when the
    /// row doesn't exist — the pre-#668 behaviour for HIG / Evolution /
    /// Archive sources.
    private func docsStructuredRow(at dbPath: URL, uri: String) -> (uri: String, kind: String)? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db
        else { return nil }
        defer { sqlite3_close_v2(db) }

        let sql = "SELECT uri, kind FROM docs_structured WHERE uri = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (uri as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let foundURI = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        let kind = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        return (uri: foundURI, kind: kind)
    }

    // MARK: - HIG

    @Test("HIGStrategy writes a docs_structured row per indexed page (#668)")
    func higWritesStructuredRow() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // Seed an on-disk HIG corpus: one category dir with one markdown page.
        let tempCorpus = FileManager.default.temporaryDirectory
            .appendingPathComponent("hig-corpus-\(UUID().uuidString)")
        let categoryDir = tempCorpus.appendingPathComponent("foundations")
        try FileManager.default.createDirectory(at: categoryDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempCorpus) }

        let pageFile = categoryDir.appendingPathComponent("color.md")
        try "# Color\n\nHIG color guidance.\n".write(to: pageFile, atomically: true, encoding: .utf8)

        let strategy = Search.HIGStrategy(higDirectory: tempCorpus, logger: Logging.NoopRecording())
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 1)
        await index.disconnect()
        // The headline assertion: post-#668 the row exists in docs_structured.
        let row = docsStructuredRow(at: dbPath, uri: "hig://foundations/color")
        #expect(row != nil, "HIG page must have a docs_structured entry (#668); pre-fix this was 100% missing")
        #expect(row?.kind == "article", "HIG markdown content classifies as `.article` kind; got \(row?.kind ?? "nil")")
    }

    // MARK: - Swift Evolution

    @Test("SwiftEvolutionStrategy writes a docs_structured row per accepted proposal (#668)")
    func swiftEvolutionWritesStructuredRow() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        let tempCorpus = FileManager.default.temporaryDirectory
            .appendingPathComponent("evolution-corpus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempCorpus, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempCorpus) }

        // Accepted-status proposal — passes the `isAcceptedProposal` gate.
        let proposal = """
        # SE-0001 Sample Feature
        * Status: **Implemented (Swift 5.0)**
        ## Introduction
        A test proposal body.
        """
        try proposal.write(
            to: tempCorpus.appendingPathComponent("SE-0001-sample.md"),
            atomically: true, encoding: .utf8
        )

        let strategy = Search.SwiftEvolutionStrategy(
            evolutionDirectory: tempCorpus, logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 1)
        await index.disconnect()
        let row = docsStructuredRow(at: dbPath, uri: "swift-evolution://SE-0001")
        #expect(row != nil, "Swift Evolution proposal must have a docs_structured entry (#668); pre-fix this was 100% missing")
        #expect(row?.kind == "article", "Swift Evolution proposals classify as `.article` kind; got \(row?.kind ?? "nil")")
    }

    // MARK: - Apple Archive

    @Test("AppleArchiveStrategy writes a docs_structured row per indexed page (#668)")
    func appleArchiveWritesStructuredRow() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        let tempCorpus = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-corpus-\(UUID().uuidString)")
        let guideDir = tempCorpus.appendingPathComponent("QuartzCoreAnimation")
        try FileManager.default.createDirectory(at: guideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempCorpus) }

        let pageFile = guideDir.appendingPathComponent("introduction.md")
        try "# Introduction\n\nLegacy Quartz programming guide body.\n".write(
            to: pageFile, atomically: true, encoding: .utf8
        )

        let strategy = Search.AppleArchiveStrategy(
            archiveDirectory: tempCorpus, logger: Logging.NoopRecording()
        )
        let stats = try await strategy.indexItems(into: index, progress: nil)

        #expect(stats.indexed == 1)
        await index.disconnect()
        let row = docsStructuredRow(at: dbPath, uri: "apple-archive://QuartzCoreAnimation/introduction")
        #expect(row != nil, "Apple Archive page must have a docs_structured entry (#668); pre-fix this was 100% missing")
        #expect(row?.kind == "article", "Apple Archive markdown content classifies as `.article` kind; got \(row?.kind ?? "nil")")
    }

    // MARK: - Helper-function unit tests

    @Test("makeArticleStructuredPage builds a page with kind=.article and source=.custom")
    func makeArticleStructuredPageShape() {
        let page = Search.StrategyHelpers.makeArticleStructuredPage(
            url: URL(string: "https://example.com/x")!,
            title: "Test Title",
            rawMarkdown: "# Body",
            crawledAt: Date(timeIntervalSince1970: 0),
            contentHash: "abc123"
        )
        #expect(page.title == "Test Title")
        #expect(page.kind == .article)
        #expect(page.source == .custom)
        #expect(page.rawMarkdown == "# Body")
        #expect(page.contentHash == "abc123")
        // Nil-defaulted fields stay nil — minimal page by design.
        #expect(page.abstract == nil)
        #expect(page.declaration == nil)
        #expect(page.module == nil)
    }

    @Test("encodeStructuredPageToJSON returns valid JSON; fallback is `{}` on failure")
    func encodeStructuredPageToJSONReturnsValidJSON() throws {
        let page = Search.StrategyHelpers.makeArticleStructuredPage(
            url: URL(string: "https://example.com/x")!,
            title: "JSON Test",
            rawMarkdown: "body",
            crawledAt: Date(timeIntervalSince1970: 0),
            contentHash: "h"
        )
        let json = Search.StrategyHelpers.encodeStructuredPageToJSON(page)
        #expect(json != "{}", "valid page should round-trip to non-empty JSON; got \(json)")
        // Sanity: decode back + compare key fields. The encoder used ISO-8601
        // for dates (so `crawledAt` is a string); the matching decoder needs
        // the same strategy to round-trip.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            Shared.Models.StructuredDocumentationPage.self,
            from: Data(json.utf8)
        )
        #expect(decoded.title == "JSON Test")
        #expect(decoded.kind == .article)
    }
}
