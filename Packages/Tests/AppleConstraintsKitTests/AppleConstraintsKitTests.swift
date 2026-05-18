@testable import AppleConstraintsKit
import Foundation
import SearchModels
import Testing

// MARK: - URIMapper

@Suite("AppleConstraintsKit.URIMapper")
struct URIMapperTests {
    @Test(
        "uri(forModule:pathComponents:) lowercases module + segments",
        arguments: [
            // (module, pathComponents, expected)
            ("SwiftUI", ["ForEach"], "apple-docs://swiftui/foreach"),
            ("SwiftUI", ["NavigationLink"], "apple-docs://swiftui/navigationlink"),
            ("SwiftUI", ["NavigationLink", "init(_:isActive:destination:)"], "apple-docs://swiftui/navigationlink/init(_:isactive:destination:)"),
            ("Foundation", ["URL"], "apple-docs://foundation/url"),
            ("UIKit", ["UIView", "frame"], "apple-docs://uikit/uiview/frame"),
        ] as [(String, [String], String)]
    )
    func roundTripsCanonicalShapes(module: String, pathComponents: [String], expected: String) {
        let actual = AppleConstraintsKit.URIMapper.uri(forModule: module, pathComponents: pathComponents)
        #expect(actual == expected, "module=\(module) path=\(pathComponents): got \(String(describing: actual)), expected \(expected)")
    }

    @Test("empty pathComponents returns nil (no symbol identity)")
    func emptyPathReturnsNil() {
        #expect(AppleConstraintsKit.URIMapper.uri(forModule: "SwiftUI", pathComponents: []) == nil)
    }

    @Test("likePrefix appends -% for hash-disambiguator matching")
    func likePrefixShape() {
        let base = "apple-docs://swiftui/foreach/init(_:content:)"
        #expect(AppleConstraintsKit.URIMapper.likePrefix(for: base) == "\(base)-%")
    }
}

// MARK: - SymbolGraph.Constraint

@Suite("AppleConstraintsKit.SymbolGraph.Constraint")
struct SymbolGraphConstraintTests {
    @Test(
        "contributesToSearchAxis: only conformance + superclass count",
        arguments: [
            ("conformance", true),
            ("superclass", true),
            ("sameType", false),
            ("layout", false),
            ("unknown-kind", false),
        ] as [(String, Bool)]
    )
    func axisFilter(kind: String, expected: Bool) {
        let c = AppleConstraintsKit.SymbolGraph.Constraint(kind: kind, lhs: "T", rhs: "Foo")
        #expect(c.contributesToSearchAxis == expected, "kind=\(kind): got \(c.contributesToSearchAxis), expected \(expected)")
    }
}

// MARK: - Extractor

@Suite("AppleConstraintsKit.Extractor")
struct ExtractorTests {
    private func makeSymbol(
        path: [String],
        kind: String = "swift.struct",
        constraints: [(String, String, String)]
    ) -> AppleConstraintsKit.SymbolGraph.Symbol {
        AppleConstraintsKit.SymbolGraph.Symbol(
            pathComponents: path,
            kind: .init(identifier: kind),
            swiftGenerics: .init(constraints: constraints.map {
                AppleConstraintsKit.SymbolGraph.Constraint(kind: $0.0, lhs: $0.1, rhs: $0.2)
            })
        )
    }

    @Test("ForEach-shaped symbol emits one entry with both rhs values")
    func foreachShape() {
        let document = AppleConstraintsKit.SymbolGraph.Document(
            module: .init(name: "SwiftUI"),
            symbols: [makeSymbol(
                path: ["ForEach"],
                constraints: [
                    ("conformance", "Data", "RandomAccessCollection"),
                    ("conformance", "ID", "Hashable"),
                ]
            )]
        )
        let entries = AppleConstraintsKit.Extractor.extractEntries(from: document)
        #expect(entries.count == 1)
        #expect(entries.first?.docURI == "apple-docs://swiftui/foreach")
        #expect(entries.first?.constraints == ["RandomAccessCollection", "Hashable"])
    }

    @Test("sameType requirements are filtered out")
    func sameTypeIsFiltered() {
        let document = AppleConstraintsKit.SymbolGraph.Document(
            module: .init(name: "Foundation"),
            symbols: [makeSymbol(
                path: ["Foo"],
                constraints: [
                    ("conformance", "T", "Collection"),
                    ("sameType", "T", "U"),
                ]
            )]
        )
        let entries = AppleConstraintsKit.Extractor.extractEntries(from: document)
        #expect(entries.count == 1)
        #expect(entries.first?.constraints == ["Collection"])
    }

    @Test("symbol with only sameType constraints emits no entry (no search-axis contribution)")
    func sameTypeOnlySkipped() {
        let document = AppleConstraintsKit.SymbolGraph.Document(
            module: .init(name: "Foundation"),
            symbols: [makeSymbol(path: ["Foo"], constraints: [("sameType", "T", "U")])]
        )
        let entries = AppleConstraintsKit.Extractor.extractEntries(from: document)
        #expect(entries.isEmpty)
    }

    @Test("symbol without swiftGenerics is skipped")
    func nonGenericSymbolSkipped() {
        let document = AppleConstraintsKit.SymbolGraph.Document(
            module: .init(name: "SwiftUI"),
            symbols: [AppleConstraintsKit.SymbolGraph.Symbol(
                pathComponents: ["Color"],
                kind: .init(identifier: "swift.struct"),
                swiftGenerics: nil
            )]
        )
        let entries = AppleConstraintsKit.Extractor.extractEntries(from: document)
        #expect(entries.isEmpty)
    }
}

// MARK: - Table round-trip

@Suite("AppleConstraintsKit.Table. Codable round-trip")
struct TableRoundTripTests {
    @Test("encode → decode preserves entries")
    func roundTrip() throws {
        let table = AppleConstraintsKit.Table(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/foreach", constraints: ["RandomAccessCollection", "Hashable"]),
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/list", constraints: ["Hashable", "View"]),
        ])
        let data = try table.jsonData()
        let decoded = try AppleConstraintsKit.Table.from(jsonData: data)
        #expect(decoded.schemaVersion == AppleConstraintsKit.Table.currentSchemaVersion)
        #expect(decoded.entries.count == 2)
    }

    @Test("newer on-disk schemaVersion is rejected")
    func futureVersionRejected() throws {
        let json = #"""
        {"schemaVersion": 99, "entries": []}
        """#
        #expect(throws: AppleConstraintsKit.Table.LoadError.self) {
            _ = try AppleConstraintsKit.Table.from(jsonData: Data(json.utf8))
        }
    }

    @Test("StaticConstraintsLookup conformance returns entries verbatim")
    func lookupReturnsEntries() async throws {
        let entries = [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/foreach", constraints: ["RandomAccessCollection", "Hashable"]),
        ]
        let table = AppleConstraintsKit.Table(entries: entries)
        let returned = try await table.allEntries()
        #expect(returned == entries)
    }

    @Test("Table.from(fileURL:) reads JSON from disk correctly (#763 acceptance)")
    func fromFileURLRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acktests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let url = tempDir.appendingPathComponent("apple-constraints.json")

        let original = AppleConstraintsKit.Table(entries: [
            Search.StaticConstraintEntry(docURI: "apple-docs://swiftui/foreach", constraints: ["View"]),
        ])
        try original.jsonData().write(to: url)

        let loaded = try AppleConstraintsKit.Table.from(fileURL: url)
        #expect(loaded.entries == original.entries)
        #expect(loaded.schemaVersion == AppleConstraintsKit.Table.currentSchemaVersion)
    }

    @Test("Table.from(fileURL:) throws on missing file (#763 acceptance)")
    func fromFileURLMissingFileThrows() throws {
        let bogus = URL(fileURLWithPath: "/tmp/this-path-does-not-exist-\(UUID().uuidString).json")
        #expect(throws: (any Error).self) {
            _ = try AppleConstraintsKit.Table.from(fileURL: bogus)
        }
    }
}

// MARK: - #763. extractEntries(from data:) JSON-Data path

@Suite("AppleConstraintsKit.Extractor — JSON Data path + decode-error contract")
struct ExtractorJSONDataPathTests {
    @Test("Valid JSON Data round-trips through extractEntries (#763 acceptance)")
    func validJSONDataReturnsEntries() throws {
        // Minimal symbol-graph shape that should produce one entry.
        let json = #"""
        {
          "metadata": {},
          "module": {"name": "SwiftUI"},
          "symbols": [
            {
              "pathComponents": ["ForEach"],
              "kind": {"identifier": "swift.struct"},
              "swiftGenerics": {
                "constraints": [
                  {"kind": "conformance", "lhs": "Data", "rhs": "RandomAccessCollection"},
                  {"kind": "conformance", "lhs": "ID", "rhs": "Hashable"}
                ]
              }
            }
          ],
          "relationships": []
        }
        """#
        let entries = try AppleConstraintsKit.Extractor.extractEntries(from: Data(json.utf8))
        #expect(entries.count == 1)
        #expect(entries.first?.docURI == "apple-docs://swiftui/foreach")
        #expect(entries.first?.constraints == ["RandomAccessCollection", "Hashable"])
    }

    @Test("Malformed JSON throws .decodeFailed with the underlying error message (#763 acceptance)")
    func malformedJSONThrowsDecodeFailed() throws {
        let bogus = Data("{ not valid json".utf8)
        do {
            _ = try AppleConstraintsKit.Extractor.extractEntries(from: bogus)
            Issue.record("extractEntries should throw on malformed JSON")
        } catch let error as AppleConstraintsKit.Extractor.Error {
            // The error carries the underlying decoder message via its
            // associated value; we don't assert on the exact text
            // (JSONDecoder messages aren't stable across Swift versions)
            // but we do assert on the case shape.
            if case let .decodeFailed(message) = error {
                #expect(!message.isEmpty, "decode-failed message should carry the underlying decoder error text")
            } else {
                Issue.record("unexpected error case: \(error)")
            }
        }
    }

    @Test("Multi-symbol document emits entries for every constraint-bearing symbol (#763 acceptance)")
    func multipleSymbolsEmitMultipleEntries() throws {
        let json = #"""
        {
          "metadata": {},
          "module": {"name": "SwiftUI"},
          "symbols": [
            {
              "pathComponents": ["ForEach"],
              "kind": {"identifier": "swift.struct"},
              "swiftGenerics": {"constraints": [{"kind": "conformance", "lhs": "Data", "rhs": "RandomAccessCollection"}]}
            },
            {
              "pathComponents": ["List"],
              "kind": {"identifier": "swift.struct"},
              "swiftGenerics": {"constraints": [{"kind": "conformance", "lhs": "Content", "rhs": "View"}]}
            },
            {
              "pathComponents": ["Color"],
              "kind": {"identifier": "swift.struct"}
            },
            {
              "pathComponents": ["Picker"],
              "kind": {"identifier": "swift.struct"},
              "swiftGenerics": {
                "constraints": [
                  {"kind": "conformance", "lhs": "Label", "rhs": "View"},
                  {"kind": "conformance", "lhs": "SelectionValue", "rhs": "Hashable"}
                ]
              }
            }
          ]
        }
        """#
        let entries = try AppleConstraintsKit.Extractor.extractEntries(from: Data(json.utf8))
        #expect(entries.count == 3, "Color has no swiftGenerics → 3 entries expected, got \(entries.count)")
        let uris = Set(entries.map(\.docURI))
        #expect(uris.contains("apple-docs://swiftui/foreach"))
        #expect(uris.contains("apple-docs://swiftui/list"))
        #expect(uris.contains("apple-docs://swiftui/picker"))
        #expect(!uris.contains("apple-docs://swiftui/color"), "no-generics symbol should not produce an entry")
    }

    @Test("superclass-kind constraint contributes to search axis (parametrised pair with conformance and sameType)")
    func superclassKindContributes() throws {
        let json = #"""
        {
          "module": {"name": "Foundation"},
          "symbols": [
            {
              "pathComponents": ["Box"],
              "kind": {"identifier": "swift.class"},
              "swiftGenerics": {
                "constraints": [
                  {"kind": "superclass", "lhs": "T", "rhs": "NSObject"},
                  {"kind": "conformance", "lhs": "U", "rhs": "Hashable"},
                  {"kind": "sameType", "lhs": "V", "rhs": "W"}
                ]
              }
            }
          ]
        }
        """#
        let entries = try AppleConstraintsKit.Extractor.extractEntries(from: Data(json.utf8))
        #expect(entries.count == 1)
        // superclass + conformance both contribute; sameType filtered out.
        #expect(entries.first?.constraints == ["NSObject", "Hashable"])
    }
}

// MARK: - #763. URIMapper edge cases

@Suite("AppleConstraintsKit.URIMapper — module + path edge cases")
struct URIMapperEdgeCaseTests {
    @Test(
        "Module names + path edge cases produce expected URIs",
        arguments: [
            // Module with `@` and underscores (real extension-file shape).
            // module.name in our extractor strips the file-name prefix and
            // just emits the module-name; we lower-case and use it raw.
            ("_WebKit_SwiftUI", ["MyType"], "apple-docs://_webkit_swiftui/mytype"),
            // pathComponents with 3+ segments (nested types).
            ("SwiftUI", ["Foo", "Bar", "baz()"], "apple-docs://swiftui/foo/bar/baz()"),
            // Already-lowercase module name passes through.
            ("foundation", ["URL"], "apple-docs://foundation/url"),
            // Paths with parens / underscores preserved un-encoded.
            ("SwiftUI", ["NavigationLink", "init(_:isActive:destination:)"], "apple-docs://swiftui/navigationlink/init(_:isactive:destination:)"),
            // Number-mixed identifier.
            ("UIKit", ["UIView2"], "apple-docs://uikit/uiview2"),
            // Multi-cap PascalCase preserved-as-lower.
            ("CoreData", ["NSManagedObject"], "apple-docs://coredata/nsmanagedobject"),
        ] as [(String, [String], String)]
    )
    func edgeCaseURIs(module: String, pathComponents: [String], expected: String) {
        let actual = AppleConstraintsKit.URIMapper.uri(forModule: module, pathComponents: pathComponents)
        #expect(actual == expected, "module=\(module) path=\(pathComponents): got \(String(describing: actual)), expected \(expected)")
    }
}
