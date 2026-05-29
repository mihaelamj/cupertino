@testable import AppleConstraintsKit
import Foundation
import SearchModels
import Testing

// MARK: - ConformanceExtractor

@Suite("AppleConstraintsKit.ConformanceExtractor")
struct ConformanceExtractorTests {
    private func symbol(path: [String], usr: String, kind: String = "swift.struct") -> AppleConstraintsKit.SymbolGraph.Symbol {
        .init(pathComponents: path, kind: .init(identifier: kind), swiftGenerics: nil, identifier: .init(precise: usr))
    }

    private func document(
        module: String,
        symbols: [AppleConstraintsKit.SymbolGraph.Symbol],
        relationships: [AppleConstraintsKit.SymbolGraph.Relationship]
    ) -> AppleConstraintsKit.SymbolGraph.Document {
        .init(module: .init(name: module), symbols: symbols, relationships: relationships)
    }

    @Test("conformsTo resolves source USR to URI and uses targetFallback's last dot-component")
    func conformsToBasic() {
        let doc = document(
            module: "SwiftUI",
            symbols: [symbol(path: ["ForEach"], usr: "s:foreach")],
            relationships: [
                .init(kind: "conformsTo", source: "s:foreach", target: "s:7SwiftUI4ViewP", targetFallback: "SwiftUICore.View"),
            ]
        )
        let entries = AppleConstraintsKit.ConformanceExtractor.extractEntries(from: doc)
        #expect(entries == [Search.StaticConformanceEntry(docURI: "apple-docs://swiftui/foreach", conformsTo: ["View"])])
    }

    @Test("multiple edges for one type merge, de-duplicated, in first-seen order; inheritsFrom counts")
    func mergesAndDedupes() {
        let doc = document(
            module: "UIKit",
            symbols: [symbol(path: ["UIButton"], usr: "s:uibutton", kind: "swift.class")],
            relationships: [
                .init(kind: "inheritsFrom", source: "s:uibutton", target: "s:uicontrol", targetFallback: "UIKit.UIControl"),
                .init(kind: "conformsTo", source: "s:uibutton", target: "s:eq", targetFallback: "Swift.Equatable"),
                .init(kind: "conformsTo", source: "s:uibutton", target: "s:eq", targetFallback: "Swift.Equatable"),
            ]
        )
        let entries = AppleConstraintsKit.ConformanceExtractor.extractEntries(from: doc)
        #expect(entries == [Search.StaticConformanceEntry(docURI: "apple-docs://uikit/uibutton", conformsTo: ["UIControl", "Equatable"])])
    }

    @Test("memberOf and other kinds are dropped")
    func dropsNonStructuralKinds() {
        let doc = document(
            module: "SwiftUI",
            symbols: [symbol(path: ["ForEach"], usr: "s:foreach")],
            relationships: [
                .init(kind: "memberOf", source: "s:foreach", target: "s:other", targetFallback: "SwiftUI.Other"),
            ]
        )
        #expect(AppleConstraintsKit.ConformanceExtractor.extractEntries(from: doc).isEmpty)
    }

    @Test("edge whose source USR is not a known symbol is skipped")
    func skipsUnknownSource() {
        let doc = document(
            module: "SwiftUI",
            symbols: [symbol(path: ["ForEach"], usr: "s:foreach")],
            relationships: [
                .init(kind: "conformsTo", source: "s:UNKNOWN", target: "s:v", targetFallback: "SwiftUICore.View"),
            ]
        )
        #expect(AppleConstraintsKit.ConformanceExtractor.extractEntries(from: doc).isEmpty)
    }

    @Test("nil/empty relationships yields no entries")
    func emptyRelationships() {
        let doc = document(module: "SwiftUI", symbols: [symbol(path: ["ForEach"], usr: "s:foreach")], relationships: [])
        #expect(AppleConstraintsKit.ConformanceExtractor.extractEntries(from: doc).isEmpty)
    }
}
