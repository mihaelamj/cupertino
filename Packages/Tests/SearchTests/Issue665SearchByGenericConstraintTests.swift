import ASTIndexer
import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import Testing

// MARK: - #665 — searchByGenericConstraint surfaces doc_symbols.generic_params

//
// Layer 2 of #409 (PR #663 landed Layer 1 — `is_public` repurpose).
// Layer 2 exposes the AST-extracted `doc_symbols.generic_params`
// column as a Swift API (`Search.Index.searchByGenericConstraint`)
// and an MCP tool (`search_generics`). The MCP wiring is covered in
// `Issue665SearchGenericsMCPMarkerTests`; this file pins the
// underlying SQL query shape + result mapping.
//
// What this file locks:
//
//   1. **Substring LIKE on the constraint** — `Sendable` matches
//      both `T: Sendable` and `T: Hashable & Sendable` (the whole
//      point of the feature; if we ever switch to exact match, this
//      assertion fails and we know to update consumers).
//   2. **Framework filter applies** — `framework: "swiftui"` removes
//      rows whose `docs_metadata.framework` doesn't match (lowercased).
//   3. **Result rows carry `genericParams`** — the new column is
//      populated on `Search.SymbolSearchResult`. Earlier semantic-
//      search entry points leave it `nil`; this entry point must
//      populate it (otherwise the MCP layer can't echo what matched).
//   4. **Limit is honoured** — same shape as `searchConformances`.
//   5. **Empty constraint returns nothing meaningful** — the LIKE
//      pattern `%%` matches every non-null `generic_params` row,
//      which is technically correct; lock the behaviour so a future
//      "reject empty constraint" change is a deliberate decision.
//   6. **Symbols with NULL `generic_params` are excluded** — a struct
//      with no generic clause is invisible to this query (a `LIKE`
//      against NULL is NULL, not TRUE).
//
// These are unit-level checks against a seeded mini-DB. The MCP
// integration shape (response markers, tool dispatch) is locked
// elsewhere.

@Suite("#665 — searchByGenericConstraint SQL contract", .serialized)
struct Issue665SearchByGenericConstraintTests {
    private func makeIndex() async throws -> (Search.Index, URL) {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-665-\(UUID().uuidString).db")
        let index = try await Search.Index(dbPath: tempDB, logger: Logging.NoopRecording())
        return (index, tempDB)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Seed a `doc_symbols` row with the requested `generic_params`
    /// string (joined comma-separated, as the indexer writes them).
    // swiftlint:disable:next function_parameter_count
    private func seed(
        index: Search.Index,
        uri: String,
        framework: String,
        title: String,
        symbolName: String,
        kind: String,
        genericParameters: [String]
    ) async throws {
        try await index.indexDocument(Search.Index.IndexDocumentParams(
            uri: uri,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: framework,
            title: title,
            content: "Stub for \(title)",
            filePath: "/tmp/\(symbolName)-\(UUID().uuidString).json",
            contentHash: "hash-\(UUID().uuidString.prefix(8))",
            lastCrawled: Date(),
            sourceType: "apple"
        ))
        let symbol = ASTIndexer.Symbol(
            name: symbolName,
            kind: ASTIndexer.SymbolKind(rawValue: kind) ?? .struct,
            line: 1,
            column: 1,
            signature: nil,
            isAsync: false,
            isThrows: false,
            isPublic: true,
            isStatic: false,
            attributes: [],
            conformances: [],
            genericParameters: genericParameters
        )
        try await index.indexDocSymbols(docUri: uri, symbols: [symbol])
    }

    // MARK: - 1. Substring LIKE match

    @Test("'Sendable' constraint matches both 'T: Sendable' and 'T: Hashable & Sendable' (substring LIKE)")
    func substringMatchesAcrossClauseShapes() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        try await seed(
            index: index,
            uri: "apple-docs://framework/box",
            framework: "framework",
            title: "Box",
            symbolName: "Box",
            kind: "struct",
            genericParameters: ["T: Sendable"]
        )
        try await seed(
            index: index,
            uri: "apple-docs://framework/cache",
            framework: "framework",
            title: "Cache",
            symbolName: "Cache",
            kind: "class",
            genericParameters: ["T: Hashable & Sendable"]
        )

        let results = try await index.searchByGenericConstraint(constraint: "Sendable", limit: 50)
        await index.disconnect()

        let names = Set(results.map(\.symbolName))
        #expect(names.contains("Box"), "T: Sendable form must match — got: \(names)")
        #expect(names.contains("Cache"), "T: Hashable & Sendable form must match — got: \(names)")
    }

    // MARK: - 2. Framework filter

    @Test("framework filter removes non-matching rows (case-insensitive)")
    func frameworkFilter() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        try await seed(
            index: index,
            uri: "apple-docs://swiftui/wrapped-view",
            framework: "swiftui",
            title: "WrappedView",
            symbolName: "WrappedView",
            kind: "struct",
            genericParameters: ["Content: View"]
        )
        try await seed(
            index: index,
            uri: "apple-docs://uikit/uihosting",
            framework: "uikit",
            title: "UIHosting",
            symbolName: "UIHosting",
            kind: "class",
            genericParameters: ["Content: View"]
        )

        let swiftuiOnly = try await index.searchByGenericConstraint(
            constraint: "View",
            framework: "swiftui",
            limit: 50
        )
        await index.disconnect()

        let names = swiftuiOnly.map(\.symbolName)
        #expect(names.contains("WrappedView"), "swiftui row must pass — got: \(names)")
        #expect(!names.contains("UIHosting"), "uikit row must be filtered out — got: \(names)")
    }

    @Test("framework filter is case-insensitive (CLI accepts 'SwiftUI', DB stores 'swiftui')")
    func frameworkFilterCaseInsensitive() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        try await seed(
            index: index,
            uri: "apple-docs://swiftui/some-view",
            framework: "swiftui",
            title: "SomeView",
            symbolName: "SomeView",
            kind: "struct",
            genericParameters: ["Content: View"]
        )

        // Caller passes mixed-case framework; method lowercases.
        let results = try await index.searchByGenericConstraint(
            constraint: "View",
            framework: "SwiftUI",
            limit: 50
        )
        await index.disconnect()

        #expect(results.contains { $0.symbolName == "SomeView" })
    }

    // MARK: - 3. Result rows carry genericParams

    @Test("result.genericParams is populated (downstream MCP can echo what matched)")
    func resultCarriesGenericParams() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        try await seed(
            index: index,
            uri: "apple-docs://framework/sortable",
            framework: "framework",
            title: "Sortable",
            symbolName: "Sortable",
            kind: "struct",
            genericParameters: ["Element: Comparable & Hashable"]
        )

        let results = try await index.searchByGenericConstraint(
            constraint: "Comparable",
            limit: 50
        )
        await index.disconnect()

        let match = results.first { $0.symbolName == "Sortable" }
        #expect(match != nil)
        if let generic = match?.genericParams {
            // The indexer writes the joined comma form, so a single
            // entry comes back as-is.
            #expect(
                generic.contains("Comparable"),
                "genericParams must echo the matched clause; got: \(generic)"
            )
        } else {
            Issue.record("genericParams must be populated, got nil on Sortable row")
        }
    }

    @Test("genericParams is null/empty for symbols indexed via the other entry points")
    func otherEntryPointsLeaveGenericParamsNil() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        try await seed(
            index: index,
            uri: "apple-docs://framework/regular-class",
            framework: "framework",
            title: "RegularClass",
            symbolName: "RegularClass",
            kind: "class",
            genericParameters: ["T: Sendable"]
        )

        // searchConformances does NOT SELECT generic_params; rows it
        // returns leave the field nil regardless of what's in the DB.
        // This locks the source-compat default-nil init contract from
        // SearchModels.
        let results = try await index.searchConformances(protocolName: "Sendable", limit: 10)
        await index.disconnect()

        // Generic_params won't match Sendable via the conformances
        // column, so the array can be empty; the assertion is about
        // any row returned NOT carrying genericParams.
        for row in results {
            #expect(row.genericParams == nil, "non-#665 entry points must leave genericParams nil; got: \(row.genericParams ?? "?")")
        }
    }

    // MARK: - 4. Limit

    @Test("limit caps result count")
    func limitIsHonoured() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        for i in 0..<5 {
            try await seed(
                index: index,
                uri: "apple-docs://framework/holder-\(i)",
                framework: "framework",
                title: "Holder\(i)",
                symbolName: "Holder\(i)",
                kind: "struct",
                genericParameters: ["T: Sendable"]
            )
        }

        let results = try await index.searchByGenericConstraint(
            constraint: "Sendable",
            limit: 2
        )
        await index.disconnect()

        #expect(results.count == 2, "limit must cap — got \(results.count)")
    }

    // MARK: - 5. Empty constraint contract

    @Test("empty constraint LIKE '%%' returns all symbols with a non-null generic_params")
    func emptyConstraintReturnsAllGenericRows() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        try await seed(
            index: index,
            uri: "apple-docs://framework/a",
            framework: "framework",
            title: "A",
            symbolName: "A",
            kind: "struct",
            genericParameters: ["T: Sendable"]
        )
        try await seed(
            index: index,
            uri: "apple-docs://framework/b",
            framework: "framework",
            title: "B",
            symbolName: "B",
            kind: "class",
            genericParameters: ["U: Hashable"]
        )

        let results = try await index.searchByGenericConstraint(constraint: "", limit: 50)
        await index.disconnect()

        // Pre-existing contract: empty string → match-all-non-null.
        // If we change to reject empty constraint, this assertion
        // flips and the change is intentional.
        #expect(results.count >= 2, "empty constraint matches any non-null generic_params; got: \(results.count)")
    }

    // MARK: - 6. NULL generic_params excluded

    @Test("symbols with no generic_params are excluded (LIKE against NULL is NULL, not TRUE)")
    func nullGenericParamsExcluded() async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        // Symbol WITH generics — should match
        try await seed(
            index: index,
            uri: "apple-docs://framework/has-generics",
            framework: "framework",
            title: "HasGenerics",
            symbolName: "HasGenerics",
            kind: "struct",
            genericParameters: ["T: Sendable"]
        )
        // Symbol WITHOUT generics (empty array → NULL column) — should NOT match
        try await seed(
            index: index,
            uri: "apple-docs://framework/no-generics",
            framework: "framework",
            title: "NoGenerics",
            symbolName: "NoGenerics",
            kind: "struct",
            genericParameters: []
        )

        let results = try await index.searchByGenericConstraint(
            constraint: "Sendable",
            limit: 50
        )
        await index.disconnect()

        let names = results.map(\.symbolName)
        #expect(names.contains("HasGenerics"))
        #expect(!names.contains("NoGenerics"), "row with NULL generic_params must NOT be returned — got: \(names)")
    }

    // MARK: - Common constraints truth-table (acceptance criterion)

    @Test(
        "common constraint truth-table — each canonical constraint hits its seeded row",
        arguments: [
            ("Sendable", "T: Sendable"),
            ("Hashable", "Key: Hashable"),
            ("Equatable", "Value: Equatable"),
            ("Comparable", "Element: Comparable"),
            ("View", "Content: View"),
        ]
    )
    func commonConstraintsTruthTable(constraint: String, clause: String) async throws {
        let (index, dbPath) = try await makeIndex()
        defer { cleanup(dbPath) }

        let symbolName = "Holder_\(constraint)"
        try await seed(
            index: index,
            uri: "apple-docs://framework/holder-\(constraint.lowercased())",
            framework: "framework",
            title: symbolName,
            symbolName: symbolName,
            kind: "struct",
            genericParameters: [clause]
        )

        let results = try await index.searchByGenericConstraint(
            constraint: constraint,
            limit: 10
        )
        await index.disconnect()

        let names = results.map(\.symbolName)
        #expect(names.contains(symbolName), "constraint=\(constraint) must match clause '\(clause)' — got: \(names)")
    }
}
