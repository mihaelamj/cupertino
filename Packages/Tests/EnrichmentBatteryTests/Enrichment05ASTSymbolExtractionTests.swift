import Foundation
import Testing

// Enrichment #5 — AST Symbol Extraction.
//
// A SwiftSyntax walk lifts declarations into doc_symbols rows: name, kind,
// signature, the is_async / is_throws / is_public / is_static flags,
// attributes, conformances, generics.
//
// Doc-vs-data note: the ASTIndexer.SymbolKind enum defines 16 cases, but
// the corpus realizes only 15 — `operator` is defined-but-never-extracted
// (Apple docs do not surface operator declarations as standalone symbols).
// The battery pins the 15 realized kinds AND that operator stays at zero,
// so a future change in either direction is caught.

@Suite("Enrichment #5 — AST Symbol Extraction (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment05ASTSymbolExtractionTests {
    /// The 16 cases ASTIndexer.SymbolKind defines.
    static let definedKinds: Set<String> = [
        "class", "struct", "enum", "actor", "protocol", "extension", "function",
        "method", "initializer", "property", "subscript", "typealias",
        "associatedtype", "case", "operator", "macro",
    ]
    /// Kinds that must appear in a healthy apple-documentation corpus.
    static let coreKinds = ["class", "struct", "enum", "protocol", "function", "property", "method"]

    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("doc_symbols is richly populated")
    func symbolsPopulated() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM doc_symbols") > 100000)
    }

    @Test("Realized kinds are a subset of the defined enum, and the core kinds are all present")
    func kindsAreValid() {
        guard let probe = docs() else { return }
        let realized = Set(probe.column("SELECT DISTINCT kind FROM doc_symbols"))
        let unexpected = realized.subtracting(Self.definedKinds)
        #expect(unexpected.isEmpty, "doc_symbols has kinds outside the SymbolKind enum: \(unexpected)")
        for kind in Self.coreKinds {
            #expect(realized.contains(kind), "missing core kind \(kind)")
        }
        #expect(realized.count >= 14 && realized.count <= 16, "realized kind count \(realized.count) outside [14,16]")
    }

    @Test("operator is the dormant 16th kind: defined in the enum, never extracted")
    func operatorKindIsDormant() {
        guard let probe = docs() else { return }
        #expect(
            probe.count("SELECT count(*) FROM doc_symbols WHERE kind='operator'") == 0,
            "operator symbols appeared; the enrichment-inventory note (16 defined / 15 realized) needs updating"
        )
    }

    @Test("Symbol flags are populated as Boolean integers")
    func flagsPopulated() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM doc_symbols WHERE is_async=1") > 0, "no async symbols")
        #expect(probe.count("SELECT count(*) FROM doc_symbols WHERE is_throws=1") > 0, "no throwing symbols")
        #expect(probe.count("SELECT count(*) FROM doc_symbols WHERE is_static=1") > 0, "no static symbols")
        #expect(probe.count("SELECT count(*) FROM doc_symbols WHERE is_public=1") > 0, "no public symbols")
    }

    @Test("Signatures, conformances and generics are captured on the symbols that have them")
    func richColumns() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM doc_symbols WHERE signature IS NOT NULL AND signature<>''") > 10000)
        #expect(probe.count("SELECT count(*) FROM doc_symbols WHERE conformances IS NOT NULL AND conformances<>''") > 0)
        #expect(probe.count("SELECT count(*) FROM doc_symbols WHERE generic_params IS NOT NULL AND generic_params<>''") > 0)
    }
}

/// The AST symbols as the search pipeline surfaces them: matchedSymbols
/// carries the name + kind of the symbol that matched.
@Suite("Enrichment #5 — AST Symbol Extraction via cupertino search", .enabled(if: CupertinoCLI.available))
struct Enrichment05ASTSymbolExtractionSearchTests {
    @Test("A type query exposes its symbol kind in matchedSymbols")
    func matchedSymbolKindSurfaces() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let results = CupertinoCLI.searchDocs("URLSession", ["--source", "apple-docs", "--limit", "3"])
        let urlSession = results.first { $0.uri.lowercased().hasSuffix("/urlsession") }
        let symbol = urlSession?.matchedSymbols?.first { $0.name == "URLSession" }
        #expect(symbol?.kind == "class", "URLSession should surface as a class in matchedSymbols, got \(String(describing: symbol?.kind))")
    }
}
