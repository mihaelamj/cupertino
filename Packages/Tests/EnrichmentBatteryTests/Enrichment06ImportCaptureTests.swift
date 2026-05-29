import Foundation
import Testing

// Enrichment #6 — Import Capture.
//
// Per-file `import X` statements plus the @_exported flag (is_exported),
// captured into doc_imports (docs), package_imports (packages), and
// file_imports (samples). Richest in the source-tree corpora (packages,
// samples); sparse in apple-docs, which is documentation rather than
// source. This is a flat per-file list, not a traversable graph.
//
// Stored metadata with no `cupertino search` filter surface, so the
// battery is DB-probe only.

@Suite("Enrichment #6 — Import Capture (real DBs)", .enabled(if: LocalDBs.anyAvailable))
struct Enrichment06ImportCaptureTests {
    @Test("packages capture a rich import list with the is_exported flag")
    func packagesImports() {
        guard LocalDBs.packagesAvailable, let probe = DBProbe(LocalDBs.packages) else { return }
        #expect(probe.tableColumns("package_imports").contains("is_exported"))
        #expect(probe.count("SELECT count(*) FROM package_imports") > 10000)
        #expect(probe.count("SELECT count(*) FROM package_imports WHERE module_name IS NOT NULL AND module_name<>''") > 10000)
    }

    @Test("samples capture per-file imports including known frameworks")
    func samplesImports() {
        guard LocalDBs.samplesAvailable, let probe = DBProbe(LocalDBs.appleSampleCode) else { return }
        #expect(probe.tableColumns("file_imports").contains("is_exported"))
        #expect(probe.count("SELECT count(*) FROM file_imports") > 5000)
        #expect(probe.count("SELECT count(*) FROM file_imports WHERE module_name='SwiftUI'") > 0, "no SwiftUI imports in samples")
    }

    @Test("apple-docs carry the doc_imports table (sparse, but present)")
    func docsImportsTablePresent() {
        guard LocalDBs.available(LocalDBs.appleDocumentation), let probe = DBProbe(LocalDBs.appleDocumentation) else { return }
        #expect(probe.hasTable("doc_imports"))
        #expect(probe.tableColumns("doc_imports").contains("is_exported"))
    }
}
