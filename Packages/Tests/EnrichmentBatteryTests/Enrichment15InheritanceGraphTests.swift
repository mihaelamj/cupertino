import Foundation
import Testing

// Enrichment #15 — Inheritance Graph.
//
// Bidirectional class-inheritance edges in the `inheritance` table
// (parent_uri -> child_uri). Conformances are NOT here (they live on the
// symbol rows, #5); this is class inheritance only. Walked by the
// `cupertino inheritance` command.

@Suite("Enrichment #15 — Inheritance Graph (real DBs)", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
struct Enrichment15InheritanceGraphTests {
    private func docs() -> DBProbe? {
        DBProbe(LocalDBs.appleDocumentation)
    }

    @Test("inheritance table has parent_uri/child_uri edges")
    func edgesExist() {
        guard let probe = docs() else { return }
        #expect(Set(probe.tableColumns("inheritance")) == ["parent_uri", "child_uri"])
        #expect(probe.count("SELECT count(*) FROM inheritance") > 1000)
    }

    @Test("A known base class has many children")
    func uiViewHasChildren() {
        guard let probe = docs() else { return }
        #expect(probe.count("SELECT count(*) FROM inheritance WHERE parent_uri LIKE '%uikit/uiview'") > 10)
    }

    @Test("The graph is bidirectional: UIView is both a parent and a child")
    func bidirectional() {
        guard let probe = docs() else { return }
        let asParent = probe.count("SELECT count(*) FROM inheritance WHERE parent_uri LIKE '%uikit/uiview'")
        let asChild = probe.count("SELECT count(*) FROM inheritance WHERE child_uri LIKE '%uikit/uiview'")
        #expect(asParent > 0 && asChild > 0, "UIView should appear as both parent (\(asParent)) and child (\(asChild))")
    }
}

/// The graph as the `cupertino inheritance` command walks it.
@Suite("Enrichment #15 — Inheritance Graph via cupertino inheritance", .enabled(if: CupertinoCLI.available))
struct Enrichment15InheritanceGraphSearchTests {
    @Test("Walking UITableView upward yields its canonical UIKit ancestor chain")
    func uiTableViewAncestors() {
        guard LocalDBs.available(LocalDBs.appleDocumentation) else { return }
        let out = CupertinoCLI.run(["inheritance", "UITableView", "--direction", "up", "--depth", "5", "--format", "json"])
        for ancestor in ["uikit/uiscrollview", "uikit/uiview", "uikit/uiresponder"] {
            #expect(out.lowercased().contains(ancestor), "UITableView ancestors should include \(ancestor)")
        }
    }
}
