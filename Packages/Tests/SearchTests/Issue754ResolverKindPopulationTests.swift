import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import SharedConstants
import Testing

// MARK: - #754 secondary: resolveSymbolURIs populates `kind` from docs_structured

//
// Companion to Issue754NSObjectResolverSuffixTests (which pinned the primary
// fix: Apple-site-suffix stripping in the SQL WHERE clause). This suite
// pins the secondary-fix SQL change: the LEFT JOIN onto docs_structured
// that populates `Search.InheritanceCandidate.kind`.
//
// Why a separate test: the helper-side test (Issue754EmptyInheritanceMessageTests
// in SearchModelsTests) doesn't reach into Search.Index. The existing
// resolver-side test (Issue754NSObjectResolverSuffixTests) doesn't seed
// docs_structured rows, so the LEFT JOIN returns NULL for kind on every
// row + the resolver returns candidate.kind == nil. That's the back-compat
// fallback path. THIS suite seeds docs_structured rows and verifies the
// kind actually populates so the formatter can pick the right reason.
//

@Suite("#754 secondary: resolveSymbolURIs populates kind from docs_structured")
struct Issue754ResolverKindPopulationTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue754-kindpop-\(UUID().uuidString).db")
    }

    /// Seed both a docs_metadata row (for the JSON-title lookup) and a
    /// docs_structured row (for the kind read by the LEFT JOIN).
    private static func indexSymbolWithKind(
        _ idx: Search.Index,
        uri: String,
        framework: String,
        title: String,
        structuredKind: Shared.Models.StructuredDocumentationPage.Kind
    ) async throws {
        let jsonData = #"{"title":"\#(title)","framework":"\#(framework)","source":"apple-docs"}"#
        try await idx.indexDocument(Search.IndexDocumentParams(
            uri: uri,
            source: "apple-docs",
            framework: framework,
            title: title,
            content: "stub for \(title)",
            filePath: "/tmp/\(framework)-\(UUID().uuidString)",
            contentHash: UUID().uuidString,
            lastCrawled: Date(),
            jsonData: jsonData
        ))
        // Index a paired docs_structured row carrying the kind.
        guard let url = URL(string: "https://developer.apple.com/documentation/\(framework)/\(title.lowercased())") else {
            return
        }
        let page = Shared.Models.StructuredDocumentationPage(
            url: url,
            title: title,
            kind: structuredKind,
            source: .appleJSON,
            contentHash: "test-\(UUID().uuidString.prefix(8))"
        )
        try await idx.indexStructuredDocument(
            uri: uri,
            source: "apple-docs",
            framework: framework,
            page: page,
            jsonData: jsonData
        )
    }

    // MARK: - Each structuredKind round-trips to InheritanceCandidate.kind

    @Test(
        "resolveSymbolURIs reads structuredKind into candidate.kind via LEFT JOIN",
        arguments: [
            (Shared.Models.StructuredDocumentationPage.Kind.class, "class"),
            (.protocol, "protocol"),
            (.struct, "struct"),
            (.enum, "enum"),
            (.actor, "actor"),
        ]
    )
    func kindRoundTrips(pair: (Shared.Models.StructuredDocumentationPage.Kind, String)) async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)

        try await Self.indexSymbolWithKind(
            idx,
            uri: "apple-docs://test/seed-\(pair.1)",
            framework: "test",
            title: "Seed\(pair.1.capitalized)",
            structuredKind: pair.0
        )

        let candidates = try await idx.resolveSymbolURIs(title: "Seed\(pair.1.capitalized)")
        #expect(candidates.count == 1, "expected one candidate for seeded symbol")
        #expect(
            candidates.first?.kind == pair.1,
            "kind=\(pair.0) should populate candidate.kind as '\(pair.1)'; got: \(candidates.first?.kind ?? "nil")"
        )
    }

    // MARK: - Back-compat: docs_metadata row without a docs_structured companion returns kind=nil

    @Test("docs_metadata row without docs_structured: candidate.kind is nil (back-compat fallback path)")
    func missingStructuredReturnsNilKind() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)

        // Index docs_metadata only; no docs_structured row.
        let jsonData = #"{"title":"OrphanSymbol","framework":"test","source":"apple-docs"}"#
        try await idx.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://test/orphan",
            source: "apple-docs",
            framework: "test",
            title: "OrphanSymbol",
            content: "stub",
            filePath: "/tmp/orphan-\(UUID().uuidString)",
            contentHash: UUID().uuidString,
            lastCrawled: Date(),
            jsonData: jsonData
        ))

        let candidates = try await idx.resolveSymbolURIs(title: "OrphanSymbol")
        #expect(candidates.count == 1)
        #expect(
            candidates.first?.kind == nil,
            "LEFT JOIN with no docs_structured row should leave kind nil; got: \(candidates.first?.kind ?? "nil")"
        )
    }
}
