import ASTIndexer
import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SharedConstants
import SQLite3
import Testing

// MARK: - #952 , searchPropertyWrappers canonical-framework boost

//
// Pre-#952 `searchPropertyWrappers(wrapper: "State")` against the
// v1.2.x bundle returned `activeSession` (from `secureelementcredential`)
// at rank-1 ahead of all 555 SwiftUI `@State` usages. The shared
// `signalRankOrderClause` tertiary tie-break is alphabetic `s.name`;
// "activeSession" sorted before "adjustBy", "alarms", etc.
//
// Post-#952 the SQL injects a tier-0 canonical-framework boost for
// the small set of Apple-defined property wrappers whose home
// frameworks are known (see `propertyWrapperCanonicalFrameworks` in
// `Search.Index.SemanticSearch.swift`). The boost is conditional,
// not unconditional: wrappers not in the table fall through to the
// original ranking.

@Suite("#952 , searchPropertyWrappers canonical-framework boost", .serialized)
struct Issue952PropertyWrapperRankingTests {
    private func makeIndex() async throws -> (Search.Index, URL) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-952-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
        return (index, tempDB)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // swiftlint:disable:next function_parameter_count
    private func seed(
        index: Search.Index,
        uri: String,
        framework: String,
        title: String,
        symbolName: String,
        kind: String,
        attributes: String? = nil
    ) async throws {
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: uri,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: framework,
            title: title,
            content: "Stub for \(title)",
            filePath: "/tmp/\(symbolName).json",
            contentHash: "hash-\(symbolName)",
            lastCrawled: Date(),
            sourceType: "apple"
        ))
        let symbol = ASTIndexer.Symbol(
            name: symbolName,
            kind: ASTIndexer.SymbolKind(rawValue: kind) ?? .property,
            line: 1,
            column: 1,
            signature: nil,
            isAsync: false,
            isThrows: false,
            isPublic: true,
            isStatic: false,
            attributes: attributes.map { $0.split(separator: ",").map { String($0) } } ?? [],
            conformances: []
        )
        try await index.indexDocSymbols(docUri: uri, symbols: [symbol])
    }

    @Test("@State usage in swiftui ranks above @State usage in secureelementcredential (alphabetic-loss reproducer)")
    func stateInSwiftUIBeatsAlphabeticFromOtherFramework() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // The v1.2.x reproducer. Pre-fix:
        //   activeSession  | secureelementcredential | @State | rank-1
        //   adjustBy       | swiftui                 | @State | rank-N
        // because "activeSession" < "adjustBy" alphabetically and
        // both share the same kind-tier + operator-tier in the
        // shared `signalRankOrderClause`. The canonical-framework
        // boost moves SwiftUI to tier 0 ahead of secureelementcredential.
        try await seed(
            index: index,
            uri: "apple-docs://secureelementcredential/activesession",
            framework: "secureelementcredential",
            title: "Active Session",
            symbolName: "activeSession",
            kind: "property",
            attributes: "@State"
        )
        try await seed(
            index: index,
            uri: "apple-docs://swiftui/adjustby",
            framework: "swiftui",
            title: "adjustBy",
            symbolName: "adjustBy",
            kind: "property",
            attributes: "@State"
        )
        let results = try await index.searchPropertyWrappers(wrapper: "State", limit: 10)
        await index.disconnect()

        let frameworks = results.map(\.framework)
        let swiftuiIdx = frameworks.firstIndex(of: "swiftui")
        let secelemIdx = frameworks.firstIndex(of: "secureelementcredential")
        #expect(swiftuiIdx != nil, "swiftui result missing: \(frameworks)")
        #expect(secelemIdx != nil, "secureelementcredential result missing: \(frameworks)")
        if let swiftuiIdx, let secelemIdx {
            #expect(
                swiftuiIdx < secelemIdx,
                "@State in swiftui must rank ABOVE @State in secureelementcredential (post-#952 canonical-framework boost). Got frameworks: \(frameworks)"
            )
        }
    }

    @Test("@State filter does not match @StateObject (precision fix)")
    func stateDoesNotMatchStateObject() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // Pre-#952 `LIKE '%@State%'` matched both `@State` and
        // `@StateObject`. Post-#952 the wrapped form
        // `(',' || s.attributes || ',') LIKE '%,@State,%'` only
        // matches the bounded `@State` token. v1.2.x bundle had
        // 21 `@StateObject` rows that were false-positive matches.
        try await seed(
            index: index,
            uri: "apple-docs://swiftui/legit-state",
            framework: "swiftui",
            title: "Legit State",
            symbolName: "legitState",
            kind: "property",
            attributes: "@State"
        )
        try await seed(
            index: index,
            uri: "apple-docs://swiftui/bogus-stateobject",
            framework: "swiftui",
            title: "Bogus StateObject",
            symbolName: "bogusStateObject",
            kind: "property",
            attributes: "@StateObject"
        )
        let results = try await index.searchPropertyWrappers(wrapper: "State", limit: 10)
        await index.disconnect()

        let names = results.map(\.symbolName)
        #expect(names.contains("legitState"), "legit @State should match (got: \(names))")
        #expect(!names.contains("bogusStateObject"), "@StateObject should NOT match @State filter post-#952 (got: \(names))")
    }

    @Test("@Observable in swiftui ranks above @Observable in other frameworks (usage-density boost)")
    func observableInSwiftUIBeatsOthers() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // v1.2.x corpus: 11 swiftui @Observable usages vs 1 observation
        // + 1 swift. The boost repoints to swiftui to surface usage
        // examples rather than the single declaration framework page.
        // Iter-2 critic finding: previous version pointed at observation
        // and would have surfaced the 1 observation row above the 11
        // swiftui rows, which inverts the user-visible improvement.
        try await seed(
            index: index,
            uri: "apple-docs://observation/azviewmodeldecl",
            framework: "observation",
            title: "AzViewModelDecl",
            symbolName: "AzViewModelDecl",
            kind: "class",
            attributes: "@Observable"
        )
        try await seed(
            index: index,
            uri: "apple-docs://swiftui/zlastmodel",
            framework: "swiftui",
            title: "ZLastModel",
            symbolName: "ZLastModel",
            kind: "class",
            attributes: "@Observable"
        )
        let results = try await index.searchPropertyWrappers(wrapper: "Observable", limit: 10)
        await index.disconnect()

        let frameworks = results.map(\.framework)
        let swiftuiIdx = frameworks.firstIndex(of: "swiftui")
        let obsIdx = frameworks.firstIndex(of: "observation")
        #expect(swiftuiIdx != nil)
        #expect(obsIdx != nil)
        if let swiftuiIdx, let obsIdx {
            #expect(swiftuiIdx < obsIdx, "@Observable in swiftui must rank ABOVE @Observable in observation (post-#952 usage-density boost). Got: \(frameworks)")
        }
    }

    @Test("@MainActor boost-set covers all 4 UI umbrellas; in-set rows cluster above out-of-set rows")
    func mainActorBoostsUIFrameworks() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // @MainActor in v1.2.x: 988 uikit, 915 swiftui, 753 appkit,
        // 713 realitykit, 1 swift sample. The boost set must include
        // all four UI frameworks (declaration is in swift, but usage
        // density is in UIKit / SwiftUI / AppKit / RealityKit).
        // Seed one row per in-set framework + one out-of-set row so
        // the test catches both the binary in/out-of-set behavior
        // AND any regression that narrows the boost set to a single
        // framework.
        try await seed(
            index: index,
            uri: "apple-docs://swift/azsampleclass",
            framework: "swift",
            title: "AzSampleClass",
            symbolName: "AzSampleClass",
            kind: "class",
            attributes: "@MainActor"
        )
        try await seed(
            index: index,
            uri: "apple-docs://uikit/uikitclass",
            framework: "uikit",
            title: "UIKitClass",
            symbolName: "UIKitClass",
            kind: "class",
            attributes: "@MainActor"
        )
        try await seed(
            index: index,
            uri: "apple-docs://swiftui/swiftuiclass",
            framework: "swiftui",
            title: "SwiftUIClass",
            symbolName: "SwiftUIClass",
            kind: "class",
            attributes: "@MainActor"
        )
        try await seed(
            index: index,
            uri: "apple-docs://appkit/appkitclass",
            framework: "appkit",
            title: "AppKitClass",
            symbolName: "AppKitClass",
            kind: "class",
            attributes: "@MainActor"
        )
        try await seed(
            index: index,
            uri: "apple-docs://realitykit/realitykitclass",
            framework: "realitykit",
            title: "RealityKitClass",
            symbolName: "RealityKitClass",
            kind: "class",
            attributes: "@MainActor"
        )
        let results = try await index.searchPropertyWrappers(wrapper: "MainActor", limit: 10)
        await index.disconnect()

        let frameworks = results.map(\.framework)
        let inSet: Set<String> = ["uikit", "swiftui", "appkit", "realitykit"]
        let firstFour = Set(frameworks.prefix(4))
        #expect(firstFour == inSet, "@MainActor's first 4 ranks must be the boost set {uikit, swiftui, appkit, realitykit} in some order; got: \(frameworks)")
        #expect(frameworks.last == "swift", "@MainActor's out-of-set framework (swift) must rank last; got: \(frameworks)")
    }

    @Test("Wrapper without canonical-framework entry falls through to original ranking")
    func unknownWrapperFallsThroughToAlphabetic() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // Synthetic wrapper name guaranteed never to exist in
        // `propertyWrapperCanonicalFrameworks` (the dictionary keys
        // are lowercase Apple-defined wrapper names; this name has
        // a synthetic marker token that would never be a real
        // Apple wrapper). If a future PR adds this exact key to the
        // dict, this test will break loudly, which is the intended
        // canary behavior for this branch.
        let syntheticWrapper = "CupertinoTestSyntheticUnknownWrapper952"
        try await seed(
            index: index,
            uri: "apple-docs://framework-a/alpha",
            framework: "framework-a",
            title: "alpha",
            symbolName: "alpha",
            kind: "property",
            attributes: "@\(syntheticWrapper)"
        )
        try await seed(
            index: index,
            uri: "apple-docs://framework-b/zulu",
            framework: "framework-b",
            title: "zulu",
            symbolName: "zulu",
            kind: "property",
            attributes: "@\(syntheticWrapper)"
        )
        let results = try await index.searchPropertyWrappers(wrapper: syntheticWrapper, limit: 10)
        await index.disconnect()

        let names = results.map(\.symbolName)
        let aIdx = names.firstIndex(of: "alpha")
        let zIdx = names.firstIndex(of: "zulu")
        #expect(aIdx != nil)
        #expect(zIdx != nil)
        if let aIdx, let zIdx {
            #expect(aIdx < zIdx, "unknown wrapper should fall through to original alphabetic ordering , got: \(names)")
        }
    }
}
