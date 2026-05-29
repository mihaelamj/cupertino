import Foundation
import Testing

// Enrichment #1 — Lexical Index.
//
// Base SQLite has no full-text search. Cupertino adds FTS5 virtual tables
// (porter unicode61 stemming) per DB: docs_fts / doc_code_fts /
// doc_symbols_fts on the docs DBs, projects_fts / files_fts /
// file_symbols_fts on samples, package_files_fts on packages.
//
// This battery proves, against the real enriched DBs, that the FTS layer
// exists, uses the expected tokenizer, stays in row-count parity with its
// base table, and answers a MATCH query.

@Suite("Enrichment #1 — Lexical Index (real DBs)", .enabled(if: LocalDBs.anyAvailable))
struct Enrichment01LexicalIndexTests {
    @Test("Every available docs DB has the three docs FTS tables", arguments: LocalDBs.docsDBs)
    func docsFTSTablesExist(db: String) {
        guard LocalDBs.available(db), let probe = DBProbe(db) else { return }
        #expect(probe.hasTable("docs_fts"), "\(db) missing docs_fts")
        #expect(probe.hasTable("doc_code_fts"), "\(db) missing doc_code_fts")
        #expect(probe.hasTable("doc_symbols_fts"), "\(db) missing doc_symbols_fts")
    }

    @Test("docs_fts uses porter unicode61 stemming", arguments: LocalDBs.docsDBs)
    func docsFTSTokenizer(db: String) {
        guard LocalDBs.available(db), let probe = DBProbe(db) else { return }
        let sql = probe.createSQL("docs_fts") ?? ""
        #expect(sql.contains("porter unicode61"), "\(db) docs_fts tokenizer not porter unicode61: \(sql)")
    }

    @Test("docs_fts is non-empty on every available docs DB", arguments: LocalDBs.docsDBs)
    func docsFTSNonEmpty(db: String) {
        guard LocalDBs.available(db), let probe = DBProbe(db) else { return }
        #expect(probe.count("SELECT count(*) FROM docs_fts") > 0, "\(db) docs_fts is empty")
    }

    @Test("A MATCH query against apple-documentation returns rows")
    func docsFTSMatchAnswers() {
        guard LocalDBs.available(LocalDBs.appleDocumentation), let probe = DBProbe(LocalDBs.appleDocumentation) else { return }
        // 'view' is a ubiquitous Apple-docs token; exact count drifts with
        // the corpus, so assert a generous floor rather than an equality.
        let hits = probe.count("SELECT count(*) FROM docs_fts WHERE docs_fts MATCH 'view'")
        #expect(hits > 1000, "expected many 'view' hits in apple-documentation, got \(hits)")
    }

    @Test("Samples DB carries projects/files/file_symbols FTS in row parity")
    func samplesFTS() {
        guard LocalDBs.samplesAvailable, let probe = DBProbe(LocalDBs.appleSampleCode) else { return }
        #expect(probe.hasTable("projects_fts"))
        #expect(probe.hasTable("files_fts"))
        #expect(probe.hasTable("file_symbols_fts"))
        let projects = probe.count("SELECT count(*) FROM projects")
        let projectsFTS = probe.count("SELECT count(*) FROM projects_fts")
        #expect(projects > 0, "no sample projects")
        #expect(projects == projectsFTS, "projects (\(projects)) vs projects_fts (\(projectsFTS)) row-count mismatch")
    }

    @Test("Packages DB carries package_files_fts in row parity with package_files")
    func packagesFTS() {
        guard LocalDBs.packagesAvailable, let probe = DBProbe(LocalDBs.packages) else { return }
        #expect(probe.hasTable("package_files_fts"))
        let files = probe.count("SELECT count(*) FROM package_files")
        let filesFTS = probe.count("SELECT count(*) FROM package_files_fts")
        #expect(files > 0, "no package files")
        #expect(files == filesFTS, "package_files (\(files)) vs package_files_fts (\(filesFTS)) row-count mismatch")
    }

    @Test("Samples + packages FTS also use porter unicode61")
    func nonDocsTokenizers() {
        if LocalDBs.samplesAvailable, let probe = DBProbe(LocalDBs.appleSampleCode) {
            #expect((probe.createSQL("projects_fts") ?? "").contains("porter unicode61"))
        }
        if LocalDBs.packagesAvailable, let probe = DBProbe(LocalDBs.packages) {
            #expect((probe.createSQL("package_files_fts") ?? "").contains("porter unicode61"))
        }
    }
}

/// Same enrichment, exercised end-to-end through `cupertino search` so the
/// FTS layer is proven to answer through the production pipeline, not just
/// in the raw table.
@Suite("Enrichment #1 — Lexical Index via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment01LexicalIndexSearchTests {
    @Test("apple-docs search returns FTS hits")
    func appleDocsSearchReturnsHits() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let results = CupertinoCLI.searchDocs("view", ["--source", "apple-docs", "--limit", "5"])
        #expect(!results.isEmpty, "expected apple-docs FTS results for 'view'")
    }

    @Test("samples search returns FTS hits")
    func samplesSearchReturnsHits() {
        guard LocalDBs.samplesAvailable else { return }
        let response = CupertinoCLI.searchSamples("swiftui", ["--limit", "5"])
        #expect(
            (response?.projects.isEmpty == false) || (response?.files.isEmpty == false),
            "expected samples FTS results for 'swiftui'"
        )
    }
}
