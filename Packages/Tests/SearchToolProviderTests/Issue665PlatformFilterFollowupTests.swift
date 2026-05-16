import ASTIndexer
import Foundation
import LoggingModels
import MCPCore
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

// MARK: - #665 follow-up — search_generics platform filter (E2E)

//
// PR #707 shipped `search_generics` as the 12th MCP tool but left its
// `--platform / --min-version` plumbing as a deliberate fast-follow
// (noted in the PR body + an inline comment in `handleSearchGenerics`).
// PR #706 (#226) had wired the 5-arg platform filter into the other 4
// AST tools (search_symbols / search_property_wrappers /
// search_concurrency / search_conformances) but #707 shipped on top so
// search_generics didn't inherit the filter.
//
// This file pins the E2E contract for the just-wired filter:
//
//   1. **No-args passthrough** — when no `min_*` is supplied, the
//      handler returns the same shape as before (the iter-7 / #665
//      semantic-marker tests still passing is the regression guard at
//      the unit level; this file's positive case re-asserts it at the
//      filter-helper seam).
//   2. **Filter-rejects-too-new** — generic-bound symbol seeded with
//      `min_ios = "18.0"`, query with `min_ios: "15.0"` (= user is on
//      iOS 15; API needs iOS 18) drops the row. Same semantic as the
//      unified `search` tool + the 4 AST tools that already use this
//      filter.
//   3. **Filter-passes-old-enough** — same seeding, query with
//      `min_ios: "18.0"` keeps the row.
//   4. **tools/list schema** — search_generics now advertises the 5
//      `min_*` schema params alongside `constraint` + `framework` +
//      `limit`.

@Suite("#665 follow-up — search_generics platform filter (E2E)")
struct Issue665PlatformFilterFollowupTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue665-platform-\(UUID().uuidString).db")
    }

    private static func makeProvider(
        seed: (Search.Index) async throws -> Void
    ) async throws -> (provider: CompositeToolProvider, cleanup: () -> Void) {
        let dbPath = tempDB()
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        try await seed(index)
        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        return (provider, {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: dbPath)
        })
    }

    /// Seed a generic-bound symbol with explicit `min_ios` metadata so
    /// the `applyPlatformFilter` post-pass can either keep or drop it
    /// based on the filter floor.
    private static func seedGenericWithIOSMinimum(
        on idx: Search.Index,
        uri: String,
        framework: String,
        title: String,
        symbolName: String,
        kind: String,
        genericParameters: [String],
        minIOS: String?
    ) async throws {
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: uri,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: framework,
            title: title,
            content: "Stub for \(title)",
            filePath: "/tmp/\(symbolName)-\(UUID().uuidString).json",
            contentHash: "hash-\(UUID().uuidString.prefix(8))",
            lastCrawled: Date(),
            minIOS: minIOS
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
        try await idx.indexDocSymbols(docUri: uri, symbols: [symbol])
    }

    // MARK: - 1. No-args passthrough

    @Test("no min_* args — search_generics returns the seeded row unchanged (regression guard)")
    func noArgsPassthrough() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedGenericWithIOSMinimum(
                on: idx,
                uri: "apple-docs://swiftui/passthrough-box",
                framework: "swiftui",
                title: "PassthroughBox",
                symbolName: "PassthroughBox",
                kind: "struct",
                genericParameters: ["T: Sendable"],
                minIOS: "18.0"
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("Sendable"),
        ]
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: args
        )
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text.contains("PassthroughBox"), "no-filter call must return the seeded row — body: \(t.text.prefix(300))")
    }

    // MARK: - 2. Filter drops too-new symbols

    @Test("min_ios floor below the row's min_ios — API too new, row dropped")
    func filterRejectsTooNewSymbols() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedGenericWithIOSMinimum(
                on: idx,
                uri: "apple-docs://swiftui/ios18-only-generic",
                framework: "swiftui",
                title: "IOS18OnlyGeneric",
                symbolName: "IOS18OnlyGeneric",
                kind: "struct",
                genericParameters: ["T: Sendable"],
                minIOS: "18.0"
            )
        }
        defer { cleanup() }
        // User says "I'm on iOS 15"; the seeded API needs iOS 18.
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("Sendable"),
            Shared.Constants.Search.schemaParamMinIOS: MCP.Core.Protocols.AnyCodable("15.0"),
        ]
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: args
        )
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(
            !t.text.contains("IOS18OnlyGeneric"),
            "iOS 18 API must be filtered out at min_ios=15.0 — body: \(t.text.prefix(300))"
        )
        #expect(
            t.text.contains("_No symbols found matching your criteria._"),
            "empty-results marker must appear post-filter — body: \(t.text.prefix(300))"
        )
    }

    // MARK: - 3. Filter keeps old-enough symbols

    @Test("min_ios floor at or above the row's min_ios — API available, row kept")
    func filterPassesOldEnoughSymbols() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedGenericWithIOSMinimum(
                on: idx,
                uri: "apple-docs://swiftui/ios14-generic",
                framework: "swiftui",
                title: "IOS14Generic",
                symbolName: "IOS14Generic",
                kind: "struct",
                genericParameters: ["T: Sendable"],
                minIOS: "14.0"
            )
        }
        defer { cleanup() }
        // User says "I'm on iOS 17"; the seeded API needs iOS 14 — passes.
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("Sendable"),
            Shared.Constants.Search.schemaParamMinIOS: MCP.Core.Protocols.AnyCodable("17.0"),
        ]
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: args
        )
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(t.text.contains("IOS14Generic"), "iOS 14 API must pass min_ios=17.0 filter — body: \(t.text.prefix(300))")
    }

    // MARK: - 4. Rows without min_ios metadata dropped when filter is active

    @Test("seeded row with no min_ios is dropped when min_ios filter is active (matches the other 4 AST tools)")
    func rowsWithoutMinimaDropped() async throws {
        let (provider, cleanup) = try await Self.makeProvider { idx in
            try await Self.seedGenericWithIOSMinimum(
                on: idx,
                uri: "apple-docs://swiftui/no-availability-generic",
                framework: "swiftui",
                title: "NoAvailabilityGeneric",
                symbolName: "NoAvailabilityGeneric",
                kind: "struct",
                genericParameters: ["T: Sendable"],
                minIOS: nil
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            Shared.Constants.Search.schemaParamConstraint: MCP.Core.Protocols.AnyCodable("Sendable"),
            Shared.Constants.Search.schemaParamMinIOS: MCP.Core.Protocols.AnyCodable("15.0"),
        ]
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: args
        )
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(
            !t.text.contains("NoAvailabilityGeneric"),
            "NULL-min_ios row must be dropped when filter is active — body: \(t.text.prefix(300))"
        )
    }

    // MARK: - 5. tools/list advertises the 5 min_* schema params

    @Test("tools/list — search_generics input schema includes min_ios / min_macos / min_tvos / min_watchos / min_visionos")
    func toolsListAdvertisesMinSchemaParams() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let listing = try await provider.listTools(cursor: nil)
        guard let tool = listing.tools.first(where: { $0.name == Shared.Constants.Search.toolSearchGenerics }) else {
            Issue.record("search_generics missing from tools/list")
            return
        }
        let propertyKeys = Set(tool.inputSchema.properties?.keys ?? [:].keys)
        #expect(propertyKeys.contains(Shared.Constants.Search.schemaParamMinIOS), "min_ios must be advertised; got: \(propertyKeys)")
        #expect(propertyKeys.contains(Shared.Constants.Search.schemaParamMinMacOS), "min_macos must be advertised; got: \(propertyKeys)")
        #expect(propertyKeys.contains(Shared.Constants.Search.schemaParamMinTvOS), "min_tvos must be advertised; got: \(propertyKeys)")
        #expect(propertyKeys.contains(Shared.Constants.Search.schemaParamMinWatchOS), "min_watchos must be advertised; got: \(propertyKeys)")
        #expect(propertyKeys.contains(Shared.Constants.Search.schemaParamMinVisionOS), "min_visionos must be advertised; got: \(propertyKeys)")
        // Existing params still present.
        #expect(propertyKeys.contains(Shared.Constants.Search.schemaParamConstraint))
        #expect(propertyKeys.contains(Shared.Constants.Search.schemaParamFramework))
        #expect(propertyKeys.contains(Shared.Constants.Search.schemaParamLimit))
    }
}
