import Foundation
import Testing

// Enrichment #16 — Code Example Extraction.
//
// Runnable code snippets pulled out of the docs into doc_code_examples
// (doc_uri, code, language, position) and indexed for full-text search via
// doc_code_fts. The FTS index is reachable through `cupertino search`
// (which searches code too), but there is no dedicated code-only search
// command, so the battery focuses on the DB.

@Suite("Enrichment #16 — Code Example Extraction (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment16CodeExampleExtractionTests {
    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("doc_code_examples is populated with non-empty code")
    func examplesPopulated() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM doc_code_examples") > 1000)
        #expect(probe.count("SELECT count(*) FROM doc_code_examples WHERE code IS NOT NULL AND code<>''") > 1000)
    }

    @Test("Examples carry a language, dominated by swift")
    func languageTagged() {
        guard let probe = docs() else { return }
        let swift = probe.count("SELECT count(*) FROM doc_code_examples WHERE language='swift'")
        let total = probe.count("SELECT count(*) FROM doc_code_examples WHERE language IS NOT NULL AND language<>''")
        #expect(swift > 0)
        #expect(swift > total / 2, "swift should dominate code examples, got \(swift)/\(total)")
    }

    @Test("Extracted code is full-text searchable via doc_code_fts")
    func codeFTSAnswers() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM doc_code_fts") > 1000)
        // A ubiquitous Swift keyword should match many indexed snippets.
        #expect(probe.count("SELECT count(*) FROM doc_code_fts WHERE doc_code_fts MATCH 'func'") > 100)
    }
}
