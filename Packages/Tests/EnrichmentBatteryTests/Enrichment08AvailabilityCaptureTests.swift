import Foundation
import Testing

// Enrichment #8 — Availability Capture.
//
// Raw @available attributes lifted from Swift source into
// files.available_attrs_json (samples). Each entry records the raw
// attribute text, the source line, and the platform tokens. This is the
// captured form; the consumed/derived forms are #3 (floors) and #17
// (aggregation), which carry the search-filter surface. Apple docs do not
// AST-parse source, so they have no available_attrs_json (they derive
// floors from DocC JSON instead). DB-probe only.

@Suite("Enrichment #8 — Availability Capture (real DBs)", .enabled(if: LocalDBs.samplesAvailable))
struct Enrichment08AvailabilityCaptureTests {
    private func samples() -> DBProbe? {
        DBProbe(LocalDBs.appleSampleCode)
    }

    @Test("files carry an available_attrs_json column")
    func columnExists() {
        guard let probe = samples() else { return }
        #expect(probe.tableColumns("files").contains("available_attrs_json"))
    }

    @Test("Some files captured @available attributes")
    func someCaptured() {
        guard let probe = samples() else { return }
        let found = probe.count(
            "SELECT count(*) FROM files WHERE available_attrs_json IS NOT NULL AND available_attrs_json NOT IN ('', '[]')"
        )
        #expect(found > 0, "no files captured @available attributes")
    }

    @Test("A captured entry is a JSON array of attributes with raw/line/platforms")
    func entryShape() {
        guard let probe = samples() else { return }
        let json = probe.text(
            "SELECT available_attrs_json FROM files WHERE available_attrs_json IS NOT NULL AND available_attrs_json NOT IN ('', '[]') LIMIT 1"
        ) ?? ""
        let data = Data(json.utf8)
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            Issue.record("available_attrs_json did not parse as a JSON array of objects: \(json)")
            return
        }
        #expect(!array.isEmpty)
        let first = array[0]
        #expect(first["raw"] != nil, "entry missing 'raw'")
        #expect(first["line"] != nil, "entry missing 'line'")
        #expect(first["platforms"] != nil, "entry missing 'platforms'")
    }
}
