import Foundation
import Testing

// Enrichment #10 — Constraint Propagation.
//
// The hierarchy pass walks the inheritance graph and accumulates a
// parent's generic constraints onto its children, so a child symbol's
// generic_constraints carries protocols it did not declare directly. The
// observable real-DB signature is multi-value (comma-joined) constraint
// lists. The pass's precise walk logic is unit-tested in the Issue759
// hierarchy suites; here we prove the accumulation actually happened in
// the shipped corpus. The resolved output is queried via #9's
// search-generics surface, so this battery is DB-probe only.

@Suite("Enrichment #10 — Constraint Propagation (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment10ConstraintPropagationTests {
    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("Multi-value constraint lists exist (accumulation signature)")
    func multiValueConstraintsExist() {
        guard let probe = docs() else { return }
        let found = probe.count("SELECT count(*) FROM doc_symbols WHERE generic_constraints LIKE '%,%'")
        #expect(found > 0, "no comma-joined constraint lists; the hierarchy pass did not accumulate")
    }

    @Test("At least one symbol carries three-plus accumulated constraints")
    func deepAccumulation() {
        guard let probe = docs() else { return }
        // length(x) - length(replace(x, ',', '')) counts commas; >= 2 commas => 3+ entries.
        let found = probe.count(
            "SELECT count(*) FROM doc_symbols WHERE (length(generic_constraints) - length(replace(generic_constraints, ',', ''))) >= 2"
        )
        #expect(found > 0, "expected symbols with 3+ accumulated constraints")
    }
}
