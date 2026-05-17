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
}
