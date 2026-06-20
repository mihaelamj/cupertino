@testable import CLI
import Foundation
import SearchModels
import Testing

/// #1162: `cupertino serve` must mirror the database-health summary and the
/// actionable "run `cupertino setup`" diagnostic to **stderr** on startup,
/// because the same lines through `Recording` land only in os.log (console
/// sink disabled to keep stdout a clean JSON-RPC channel) — invisible to an
/// operator watching the server-output (stderr) panel. The I/O is a thin
/// `fputs` shell in `serve`; the line content is `serveDatabaseHealthBanner`,
/// a pure function pinned here.
@Suite("CLIImpl.serveDatabaseHealthBanner (#1162)")
struct Issue1162ServeStartupBannerTests {
    private func item(_ id: String, present: Bool, schema: Int = 18) -> Search.SourceInventoryItem {
        Search.SourceInventoryItem(
            id: id,
            sourceID: id,
            displayName: id.capitalized,
            filename: "\(id).db",
            present: present,
            schemaVersion: present ? schema : 0
        )
    }

    @Test("complete corpus + healthy index: a single all-installed line, no setup hint")
    func completeCorpusOneLine() {
        let inventory = Search.SourceInventory(sources: [
            item("apple-documentation", present: true),
            item("hig", present: true),
        ])
        let lines = CLIImpl.serveDatabaseHealthBanner(
            inventory: inventory,
            searchIndexDisabledReason: nil,
            commandName: "cupertino"
        )
        #expect(lines == ["📚 Databases: all 2 installed."])
    }

    @Test("partial corpus: names the missing sources and prints the setup remediation")
    func partialCorpusListsMissingAndHint() {
        let inventory = Search.SourceInventory(sources: [
            item("apple-documentation", present: true),
            item("hig", present: false),
            item("swift-org", present: false),
        ])
        let lines = CLIImpl.serveDatabaseHealthBanner(
            inventory: inventory,
            searchIndexDisabledReason: nil,
            commandName: "cupertino"
        )
        #expect(lines.first == "📚 Databases: 1 of 3 installed. Missing: hig, swift-org.")
        // The actionable remediation must be present and name the binary.
        #expect(lines.contains { $0.contains("Run `cupertino setup`") })
        // Non-vacuous: an all-present inventory would NOT carry the hint.
        #expect(lines.count == 2)
    }

    @Test("schema mismatch on a present corpus surfaces the disabled reason, no false missing")
    func schemaMismatchSurfacesReason() {
        let inventory = Search.SourceInventory(sources: [
            item("apple-documentation", present: true),
            item("hig", present: true),
        ])
        let lines = CLIImpl.serveDatabaseHealthBanner(
            inventory: inventory,
            searchIndexDisabledReason: "schema mismatch; run `cupertino setup` to redownload a matching bundle",
            commandName: "cupertino"
        )
        // Present corpus → summary carries no "Missing:" and no setup hint
        // (nothing is missing), but the index reason is surfaced.
        #expect(lines.first == "📚 Databases: 2 of 2 installed.")
        #expect(lines.contains { $0.hasPrefix("⚠️  Search index unavailable:") })
        #expect(!lines.contains { $0.contains("Missing:") })
        #expect(!lines.contains { $0.contains("Run `cupertino setup`") })
    }

    @Test("empty corpus: 0-of-0 still produces a non-empty banner")
    func emptyCorpusNonEmpty() {
        let lines = CLIImpl.serveDatabaseHealthBanner(
            inventory: Search.SourceInventory(sources: []),
            searchIndexDisabledReason: nil,
            commandName: "cupertino"
        )
        #expect(lines == ["📚 Databases: all 0 installed."])
    }
}
