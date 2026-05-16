import ASTIndexer
import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import SQLite3
import Testing

// MARK: - #177 — AST semantic search reranks operator/synthesised symbols last

//
// Pre-fix every AST semantic query (`searchSymbols`, `searchPropertyWrappers`,
// `searchConcurrencyPatterns`, `searchConformances`) used a flat
// `ORDER BY s.name`, which surfaced `==(_:_:)` operator overloads and
// synthesised `Equatable` / `Hashable` / `Comparable` conformance
// members ahead of canonical type pages. Searching for `mainactor`
// returned `==` operators from RealityKit before any view-model class;
// `task` returned `==` / `<=` / `<` on `Task<Success, Failure>` and
// `TaskPriority` before any real Task usage.
//
// Post-fix the shared `signalRankOrderClause` (private file-level
// constant) reranks in two tiers:
//   1. Rows whose symbol name is one of the operator-overload /
//      synthesised-conformance names (`==(_:_:)`, `hash(into:)`, …)
//      go LAST among everything else.
//   2. Within tier 1, canonical type kinds (class / struct / enum /
//      protocol / actor) come first; type-shape sub-kinds (typealias /
//      macro); member-shape; `kind=operator` next; everything else
//      (including `kind=unknown`) last.
//
// `s.name` is the secondary tie-breaker — preserves the pre-fix
// alphabetic shape inside each bucket.
//
// Does NOT exclude — pre-fix workflows that wanted "all results
// including operators" still get them, just lower in the list.

@Suite("#177 — AST semantic search signal-rank reranking", .serialized)
struct Issue177SemanticSearchRerankTests {
    private func makeIndex() async throws -> (Search.Index, URL) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-177-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording())
        return (index, tempDB)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Seed a `doc_symbols` row backed by a real `docs_metadata` +
    /// `docs_fts` parent so the SQL JOINs in the semantic-search
    /// queries return it.
    // swiftlint:disable:next function_parameter_count
    private func seed(
        index: Search.Index,
        uri: String,
        framework: String,
        title: String,
        symbolName: String,
        kind: String,
        attributes: String? = nil,
        conformances: String? = nil
    ) async throws {
        try await index.indexDocument(Search.Index.IndexDocumentParams(
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
        // Raw SQL insert into doc_symbols + doc_symbols_fts; bypassing
        // the indexer's normal AST-extraction path so the test can
        // construct precise kind+name+attribute combinations.
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-177-seed-stage.db")
        _ = dbPath // marker — not used; insert via index.indexDocSymbols below
        let symbol = ASTIndexer.Symbol(
            name: symbolName,
            kind: ASTIndexer.SymbolKind(rawValue: kind) ?? .function,
            line: 1,
            column: 1,
            signature: nil,
            isAsync: false,
            isThrows: false,
            isPublic: false,
            isStatic: false,
            attributes: attributes.map { $0.split(separator: ",").map { String($0) } } ?? [],
            conformances: conformances.map { $0.split(separator: ",").map { String($0) } } ?? []
        )
        try await index.indexDocSymbols(docUri: uri, symbols: [symbol])
    }

    @Test("searchPropertyWrappers — actual #177 repro: @MainActor on operator overload ranks below @MainActor on class")
    func mainActorRepro() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // The actual #177 reproducer from the issue body. Pre-fix,
        // `searchPropertyWrappers(wrapper: "MainActor")` returned the
        // `==(_:_:)` operator overload from a @MainActor struct
        // BEFORE the @MainActor view-controller class because
        // `==` < `V` alphabetically. Post-fix the operator name hits
        // tier-1 penalty + the canonical class kind beats operator
        // kind on tier-2, so the class wins decisively.
        try await seed(
            index: index,
            uri: "apple-docs://realitykit/audio-equality",
            framework: "realitykit",
            title: "Audio Equality",
            symbolName: "==(_:_:)",
            kind: "operator",
            attributes: "@MainActor"
        )
        try await seed(
            index: index,
            uri: "apple-docs://swiftui/view-model",
            framework: "swiftui",
            title: "ViewModel",
            symbolName: "ViewModel",
            kind: "class",
            attributes: "@MainActor"
        )
        let results = try await index.searchPropertyWrappers(wrapper: "MainActor", limit: 10)
        await index.disconnect()

        let names = results.map(\.symbolName)
        let classIdx = names.firstIndex(of: "ViewModel")
        let opIdx = names.firstIndex(of: "==(_:_:)")
        #expect(classIdx != nil, "class result missing: \(names)")
        #expect(opIdx != nil, "operator result missing: \(names)")
        if let classIdx, let opIdx {
            #expect(classIdx < opIdx, "@MainActor class should rank ABOVE @MainActor operator overload — got names: \(names)")
        }
    }

    @Test("searchPropertyWrappers still RETURNS operator overloads (deprioritise, not exclude)")
    func stillReturnsOperators() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        try await seed(
            index: index,
            uri: "apple-docs://framework/audio-equality",
            framework: "framework",
            title: "Audio Equality",
            symbolName: "==(_:_:)",
            kind: "operator",
            attributes: "@MainActor"
        )
        let results = try await index.searchPropertyWrappers(wrapper: "MainActor", limit: 10)
        await index.disconnect()

        #expect(results.contains { $0.symbolName == "==(_:_:)" }, "operator overload should still be returned, just ranked lower; got: \(results.map(\.symbolName))")
    }

    @Test("searchConformances reranks canonical-kind matches above synthesised hash(into:)")
    func searchConformancesRanksTypeAboveHashInto() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        try await seed(
            index: index,
            uri: "apple-docs://framework/hashable-anchor",
            framework: "framework",
            title: "HashableAnchor",
            symbolName: "hash(into:)",
            kind: "method",
            conformances: "Hashable"
        )
        try await seed(
            index: index,
            uri: "apple-docs://framework/hashable-thing",
            framework: "framework",
            title: "HashableThing",
            symbolName: "HashableThing",
            kind: "struct",
            conformances: "Hashable"
        )
        let results = try await index.searchConformances(protocolName: "Hashable", limit: 10)
        await index.disconnect()

        let names = results.map(\.symbolName)
        let typeIdx = names.firstIndex(of: "HashableThing")
        let hashIdx = names.firstIndex(of: "hash(into:)")
        #expect(typeIdx != nil)
        #expect(hashIdx != nil)
        if let typeIdx, let hashIdx {
            #expect(typeIdx < hashIdx, "type with Hashable conformance should rank ABOVE the synthesised hash(into:) — got: \(names)")
        }
    }

    @Test("kind-tier ordering: class beats typealias beats method beats operator")
    func kindTierOrdering() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // Same name shape (`ZSearchTarget`); same tier-1 (none are
        // operator-shaped names); differentiated only by kind. Tier-2
        // dictates the order. ASTIndexer.SymbolKind doesn't have an
        // `unknown` case (Swift parser always assigns one), so the
        // fourth row uses `operator` kind which is the catch-all next
        // to "everything else" in tier-2.
        try await seed(
            index: index,
            uri: "apple-docs://framework/zzz-method",
            framework: "framework",
            title: "ZzzMethod",
            symbolName: "ZSearchTarget",
            kind: "method"
        )
        try await seed(
            index: index,
            uri: "apple-docs://framework/zzz-class",
            framework: "framework",
            title: "ZzzClass",
            symbolName: "ZSearchTarget",
            kind: "class"
        )
        try await seed(
            index: index,
            uri: "apple-docs://framework/zzz-typealias",
            framework: "framework",
            title: "ZzzTypealias",
            symbolName: "ZSearchTarget",
            kind: "typealias"
        )
        try await seed(
            index: index,
            uri: "apple-docs://framework/zzz-operator",
            framework: "framework",
            title: "ZzzOperator",
            symbolName: "ZSearchTarget",
            kind: "operator"
        )
        let results = try await index.searchSymbols(query: "ZSearchTarget", limit: 10)
        await index.disconnect()

        let kinds = results.map(\.symbolKind)
        #expect(kinds == ["class", "typealias", "method", "operator"], "expected canonical-type-first ordering; got \(kinds)")
    }
}
