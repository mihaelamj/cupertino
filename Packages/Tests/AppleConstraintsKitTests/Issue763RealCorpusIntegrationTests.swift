@testable import AppleConstraintsKit
import Foundation
import SearchModels
import Testing

// MARK: - #763 / #764 consumer-side proof against real cupertino-symbolgraphs corpus

//
// Consumer-side integration tests added per main's audit-help-request
// (2026-05-18). The producer (cupertino-symbolgraphs v0.1.0) emits
// real symbol-graph .symbols.json files; this file proves that
// `AppleConstraintsKit` reads them correctly via two complementary
// surfaces:
//
//   1. CI-safe synthetic-fixture tests: an inline .symbols.json
//      string literal that matches the on-the-wire shape Apple emits.
//      Pins the SHAPE contract without any external dependency. Runs
//      in every CI build.
//
//   2. Local-only real-corpus tests: load actual files from
//      `/tmp/cupertino-corpus/unpacked/` (the artefact produced by
//      `gh release download v0.1.0 -R mihaelamj/cupertino-symbolgraphs
//      -p 'corpus-v0.1.0.zip'`). Run when the corpus is staged
//      locally; auto-disabled when not. Pins the REAL DATA contract.
//
// Both ends meet in the middle: producer guarantees the corpus by its
// own schema (cupertino-symbolgraphs tests); this file guarantees the
// consumer reads it. Two independent decoders agreeing is the
// strongest available correctness guarantee without the 11h re-save.

private enum LocalCorpus {
    /// Conventional unpacked-corpus location used by the #763 / #764
    /// session. Tests check this before running real-data assertions;
    /// `enabled(if:)` short-circuits when absent.
    static let unpackedDir = "/tmp/cupertino-corpus/unpacked"

    /// Full-corpus filtered table emitted by `cupertino-constraints-gen
    /// --from-directory unpacked -o /tmp/apple-constraints-full.json`.
    /// Snapshot from the 2026-05-18 validation: 61,031 entries / 10.48
    /// MB. Asserts below use a generous floor (50_000) so a future
    /// Apple SDK with more symbols doesn't break this test.
    static let fullTablePath = "/tmp/apple-constraints-full.json"

    /// True when the unpacked SwiftUI symbol-graph is reachable.
    /// Drives `.enabled(if:)` on the real-corpus suite.
    static var swiftUIAvailable: Bool {
        FileManager.default.fileExists(atPath: "\(unpackedDir)/swiftui/SwiftUI.symbols.json")
    }

    /// True when the full-corpus apple-constraints.json is reachable.
    static var fullTableAvailable: Bool {
        FileManager.default.fileExists(atPath: fullTablePath)
    }

    /// True when at least Foundation + UIKit + SwiftUI graphs are
    /// reachable. Drives the multi-framework decode test.
    static var multiFrameworkAvailable: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: "\(unpackedDir)/swiftui/SwiftUI.symbols.json")
            && fm.fileExists(atPath: "\(unpackedDir)/foundation/Foundation.symbols.json")
            && fm.fileExists(atPath: "\(unpackedDir)/uikit/UIKit.symbols.json")
    }
}

// MARK: - CI-safe: synthetic-fixture shape contract

@Suite("#763. SymbolGraph Codable on real-shape synthetic fixture (CI-safe)")
struct SymbolGraphShapeContractTests {
    /// Inline .symbols.json that matches Apple's on-the-wire shape
    /// (verified empirically against cupertino-symbolgraphs v0.1.0
    /// SwiftUI output). Carries the fields our Codable reads PLUS
    /// extra fields the Codable should drop silently. The synthetic
    /// shape is what cupertino-symbolgraphs v0.1.0 actually emits;
    /// changing it requires re-validation against the producer.
    static let realShapeFixture = #"""
    {
      "metadata": {
        "formatVersion": {"major": 0, "minor": 6, "patch": 0},
        "generator": "Swift version 6.2 (swift-6.2-RELEASE)"
      },
      "module": {
        "name": "SwiftUI",
        "platform": {
          "architecture": "arm64",
          "vendor": "apple",
          "operatingSystem": {"name": "macosx", "minimumVersion": {"major": 26, "minor": 0, "patch": 0}}
        }
      },
      "symbols": [
        {
          "kind": {"identifier": "swift.struct", "displayName": "Structure"},
          "identifier": {"precise": "s:7SwiftUI7ForEachV", "interfaceLanguage": "swift"},
          "pathComponents": ["ForEach"],
          "names": {"title": "ForEach"},
          "swiftGenerics": {
            "parameters": [
              {"name": "Data", "index": 0, "depth": 0},
              {"name": "ID", "index": 1, "depth": 0},
              {"name": "Content", "index": 2, "depth": 0}
            ],
            "constraints": [
              {"kind": "conformance", "lhs": "Data", "rhs": "RandomAccessCollection", "rhsPrecise": "s:Sk"},
              {"kind": "conformance", "lhs": "ID", "rhs": "Hashable", "rhsPrecise": "s:SH"}
            ]
          }
        },
        {
          "kind": {"identifier": "swift.method", "displayName": "Instance Method"},
          "identifier": {"precise": "s:7SwiftUI4ViewPAAE4bodyQrvp", "interfaceLanguage": "swift"},
          "pathComponents": ["View", "body"],
          "names": {"title": "body"}
        }
      ],
      "relationships": [
        {"kind": "conformsTo", "source": "s:7SwiftUI7ForEachV", "target": "s:7SwiftUI4ViewP"}
      ]
    }
    """#

    @Test("Real-shape synthetic .symbols.json decodes via AppleConstraintsKit.SymbolGraph.Document")
    func realShapeDecodes() throws {
        let data = Data(Self.realShapeFixture.utf8)
        let doc = try JSONDecoder().decode(AppleConstraintsKit.SymbolGraph.Document.self, from: data)
        #expect(doc.module.name == "SwiftUI")
        #expect(doc.symbols.count == 2)
    }

    @Test("Extractor against real-shape fixture emits ForEach entry with expected constraints")
    func realShapeExtractsForEach() throws {
        let data = Data(Self.realShapeFixture.utf8)
        let entries = try AppleConstraintsKit.Extractor.extractEntries(from: data)
        #expect(entries.count == 1, "ForEach is the only symbol with constraints; got \(entries.count)")
        let foreach = entries.first
        #expect(foreach?.docURI == "apple-docs://swiftui/foreach")
        #expect(foreach?.constraints == ["RandomAccessCollection", "Hashable"])
    }

    @Test("Decoder silently drops unknown top-level + nested fields (forward-compat)")
    func forwardCompatibleDecode() throws {
        // Add a top-level field our model doesn't know about; decode
        // should still succeed. This pins forward-compat: if Apple
        // adds a new field to symbol-graphs we still decode cleanly.
        let json = Self.realShapeFixture.replacingOccurrences(
            of: "\"relationships\":",
            with: "\"unknownFutureField\": {\"foo\": \"bar\"}, \"relationships\":"
        )
        _ = try JSONDecoder().decode(AppleConstraintsKit.SymbolGraph.Document.self, from: Data(json.utf8))
    }
}

// MARK: - Local-only: real corpus

@Suite("#763. real cupertino-symbolgraphs v0.1.0 corpus (local-only, /tmp)", .serialized)
struct RealCorpusIntegrationTests {
    @Test(
        "SwiftUI.symbols.json from v0.1.0 corpus decodes and extracts > 1,000 entries",
        .enabled(if: LocalCorpus.swiftUIAvailable)
    )
    func swiftUIRealCorpusExtraction() throws {
        let path = "\(LocalCorpus.unpackedDir)/swiftui/SwiftUI.symbols.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let entries = try AppleConstraintsKit.Extractor.extractEntries(from: data)
        // SwiftUI is constraint-heavy; the v0.1.0 corpus had 22k+ entries
        // when combined with extension files. The main file alone is
        // smaller but should still be in the thousands. Generous floor.
        #expect(entries.count > 1000, "SwiftUI.symbols.json should yield > 1,000 constraint entries; got \(entries.count)")
    }

    @Test(
        "SwiftUI OutlineGroup entry: docURI shape + RandomAccessCollection + Hashable constraints",
        .enabled(if: LocalCorpus.swiftUIAvailable)
    )
    func swiftUIOutlineGroupEntryShape() throws {
        // OutlineGroup<Data, ID, Content> where Data: RandomAccessCollection,
        // ID: Hashable. Chosen as the canonical iter-3 demo case
        // because OutlineGroup's struct decl IS in
        // SwiftUI.symbols.json directly, unlike ForEach which lives
        // in the SwiftUICore submodule and isn't part of the SwiftUI
        // standalone symbol-graph.
        let path = "\(LocalCorpus.unpackedDir)/swiftui/SwiftUI.symbols.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let entries = try AppleConstraintsKit.Extractor.extractEntries(from: data)
        let outline = entries.first { $0.docURI == "apple-docs://swiftui/outlinegroup" }
        let unwrapped = try #require(outline, "OutlineGroup entry must be present in SwiftUI corpus")
        #expect(unwrapped.constraints.contains("RandomAccessCollection"), "OutlineGroup constraints must include RandomAccessCollection; got \(unwrapped.constraints)")
        #expect(unwrapped.constraints.contains("Hashable"), "OutlineGroup constraints must include Hashable; got \(unwrapped.constraints)")
    }

    @Test(
        "Full apple-constraints.json (pipeline output) round-trips through AppleConstraintsKit.Table",
        .enabled(if: LocalCorpus.fullTableAvailable)
    )
    func fullTableRoundTrip() throws {
        let table = try AppleConstraintsKit.Table.from(
            fileURL: URL(fileURLWithPath: LocalCorpus.fullTablePath)
        )
        #expect(table.schemaVersion == AppleConstraintsKit.Table.currentSchemaVersion)
        #expect(table.entries.count > 50000, "Full v0.1.0 corpus should produce > 50,000 filtered entries; got \(table.entries.count)")
        // OutlineGroup is the canonical iter-3 demo case present in
        // the corpus (see swiftUIOutlineGroupEntryShape note above on
        // why ForEach isn't usable as the anchor).
        let outline = table.entries.first { $0.docURI == "apple-docs://swiftui/outlinegroup" }
        let unwrapped = try #require(outline, "Full table must include SwiftUI OutlineGroup")
        #expect(unwrapped.constraints.contains("RandomAccessCollection"))
        #expect(unwrapped.constraints.contains("Hashable"))
    }

    @Test(
        "Multi-framework decode: SwiftUI + Foundation + UIKit all parse without throwing",
        .enabled(if: LocalCorpus.multiFrameworkAvailable)
    )
    func multiFrameworkDecode() throws {
        let frameworks = [
            ("swiftui", "SwiftUI"),
            ("foundation", "Foundation"),
            ("uikit", "UIKit"),
        ]
        for (slug, module) in frameworks {
            let path = "\(LocalCorpus.unpackedDir)/\(slug)/\(module).symbols.json"
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            // Decode-only assertion (no entry-count floor on Foundation/UIKit ,
            // those framework shapes differ from SwiftUI's generic-heavy
            // posture; we're proving the CODEC works, not the data shape).
            let doc = try JSONDecoder().decode(AppleConstraintsKit.SymbolGraph.Document.self, from: data)
            #expect(doc.module.name == module, "\(module).symbols.json module.name should equal \(module); got \(doc.module.name)")
        }
    }

    @Test(
        "Pipeline output (full table) parses + 60k+ entries verified at runtime against snapshot",
        .enabled(if: LocalCorpus.fullTableAvailable)
    )
    func pipelineOutputSnapshot() throws {
        // Snapshot from 2026-05-18 cupertino-symbolgraphs v0.1.0 run:
        // 61,031 entries / 10.48 MB / schemaVersion 1. Snapshot is a
        // floor. Apple ships new symbols every SDK, so the count may
        // grow but not shrink below this without a real reason.
        let data = try Data(contentsOf: URL(fileURLWithPath: LocalCorpus.fullTablePath))
        let table = try AppleConstraintsKit.Table.from(jsonData: data)
        #expect(table.entries.count >= 60000, "Pipeline-output snapshot floor: 61,031 entries; got \(table.entries.count). A drop below 60k means upstream regression.")
        #expect(table.schemaVersion == 1, "Pipeline output should target schemaVersion 1; got \(table.schemaVersion)")
    }
}
