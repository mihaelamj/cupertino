import AppleConstraintsKit
@testable import CLI
import Foundation
import SearchModels
import Testing

/// #1144: enrichment inputs are read LAZILY at the enrichment phase, not at
/// save start. A file produced AFTER the lookup is constructed (mimicking an
/// operator running `cupertino-constraints-gen` while a long index runs) is
/// still read. A missing file yields an empty table (best-effort, no throw).
@Suite("#1144 lazy enrichment lookups")
struct Issue1144LazyEnrichmentLookupTests {
    private static func absentURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lazy-absent-\(UUID().uuidString).json")
    }

    @Test("missing constraints file: empty, no throw")
    func missingConstraints() async throws {
        let entries = try await LazyConstraintsLookup(path: Self.absentURL()).allEntries()
        #expect(entries.isEmpty)
    }

    @Test("missing conformances file: empty, no throw")
    func missingConformances() async throws {
        let entries = try await LazyConformancesLookup(path: Self.absentURL()).allConformanceEntries()
        #expect(entries.isEmpty)
    }

    @Test("constraints file produced AFTER the lookup is created is still read")
    func deferredConstraintsRead() async throws {
        let url = Self.absentURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // Construct the lookup while the file does NOT exist yet.
        let lookup = LazyConstraintsLookup(path: url)
        // Produce the file afterwards (mimics produce-during-save).
        let table = AppleConstraintsKit.Table(
            entries: [Search.StaticConstraintEntry(docURI: "apple-docs://x/y", constraints: ["View"])]
        )
        try table.jsonData().write(to: url)
        // First query happens only now, at "enrichment time".
        let entries = try await lookup.allEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.docURI == "apple-docs://x/y")
        #expect(entries.first?.constraints == ["View"])
    }

    @Test("conformances file produced AFTER the lookup is created is still read")
    func deferredConformancesRead() async throws {
        let url = Self.absentURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let lookup = LazyConformancesLookup(path: url)
        let table = AppleConstraintsKit.ConformanceTable(
            entries: [Search.StaticConformanceEntry(docURI: "apple-docs://a/b", conformsTo: ["Equatable"])]
        )
        try table.jsonData().write(to: url)
        let entries = try await lookup.allConformanceEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.docURI == "apple-docs://a/b")
        #expect(entries.first?.conformsTo == ["Equatable"])
    }
}
