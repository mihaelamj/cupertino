import Foundation
import LoggingModels
@testable import Search
import SearchModels
@testable import SearchSQLite
import Testing

// MARK: - #754 — resolveSymbolURIs handles Apple's site-suffix title shape

//
// Surface during 2026-05-17 MCP-tools-sanity probe: `get_inheritance(symbol: "NSObject")`
// returned "No symbol named `NSObject` in apple-docs" even though NSObject is in
// the corpus (UIView's ancestor walk does reach the NSObject row in the inheritance
// edges; the symbol-name → URI resolver was the gap).
//
// Root cause: `json_data.$.title` is stored in two shapes across the v1.2.0 corpus
// (~37% suffixed / ~63% bare):
//   - bare:     `"UIView"`
//   - suffixed: `"NSObject | Apple Developer Documentation"`
// Pre-fix the resolver predicate only matched the bare form, so high-traffic root
// types (NSObject, NSResponder, etc.) whose stored title carries Apple's HTML
// page-title site suffix were unreachable by name lookup.
//
// Fix: SQL-side, strip the ` | Apple Developer Documentation` suffix via REPLACE
// before the lowercase equality compare. Works for both shapes (REPLACE on the
// bare form is a no-op; REPLACE on the suffixed form strips to the bare form).
//
// This suite is the regression lock. Parametrised over 10 canonical root types
// chosen to cover the surface Apple's docs frame as "common inheritance roots"
// across UIKit / AppKit / Foundation / Core* / Objective-C. Each is constructed
// with BOTH stored-title shapes (bare + suffixed) to prove the fix handles both.

@Suite("#754 — resolveSymbolURIs strips Apple site-suffix", .serialized)
struct Issue754NSObjectResolverSuffixTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue754-resolver-\(UUID().uuidString).db")
    }

    /// Seed one apple-docs row with the requested title shape.
    /// The resolver reads from `docs_metadata.json_data.$.title`.
    private static func indexSymbol(
        _ idx: Search.Index,
        uri: String,
        framework: String,
        storedTitle: String
    ) async throws {
        // Embed the title verbatim in json_data so the resolver's
        // `json_extract(json_data, '$.title')` sees exactly the shape
        // under test. Escape the JSON manually since the suffixed form
        // contains a literal pipe (no JSON-special chars in either shape
        // we test, but tolerate `"` by avoiding it).
        let jsonData = #"{"title":"\#(storedTitle)","kind":"class","framework":"\#(framework)","source":"apple-docs"}"#
        try await idx.indexDocument(Search.IndexDocumentParams(
            uri: uri,
            source: "apple-docs",
            framework: framework,
            title: storedTitle,
            content: "stub content for \(storedTitle)",
            filePath: "/tmp/\(framework)-\(UUID().uuidString)",
            contentHash: UUID().uuidString,
            lastCrawled: Date(),
            jsonData: jsonData
        ))
    }

    /// 10 canonical root types per the #754 acceptance bar. Each is
    /// (user-typed bare name, URI, framework). Suffix shape applied
    /// per-test by the parametrised test below.
    private static let canonicalRoots: [(name: String, uri: String, framework: String)] = [
        ("NSObject", "apple-docs://objectivec/nsobject-swift.class", "objectivec"),
        ("NSResponder", "apple-docs://appkit/nsresponder", "appkit"),
        ("UIView", "apple-docs://uikit/uiview", "uikit"),
        ("UIResponder", "apple-docs://uikit/uiresponder", "uikit"),
        ("UIViewController", "apple-docs://uikit/uiviewcontroller", "uikit"),
        ("NSView", "apple-docs://appkit/nsview", "appkit"),
        ("NSViewController", "apple-docs://appkit/nsviewcontroller", "appkit"),
        ("CALayer", "apple-docs://quartzcore/calayer", "quartzcore"),
        ("NSManagedObject", "apple-docs://coredata/nsmanagedobject", "coredata"),
        ("UIControl", "apple-docs://uikit/uicontrol", "uikit"),
    ]

    // MARK: - Suffixed-title shape (the bug surface)

    @Test(
        "resolveSymbolURIs finds canonical root types whose stored title carries Apple's site suffix",
        arguments: canonicalRoots
    )
    func resolveSuffixedTitleShape(root: (name: String, uri: String, framework: String)) async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)

        // Seed with the SUFFIXED form Apple's DocC writes for these pages.
        let suffixedTitle = "\(root.name) | Apple Developer Documentation"
        try await Self.indexSymbol(
            idx,
            uri: root.uri,
            framework: root.framework,
            storedTitle: suffixedTitle
        )

        // User types the bare name. Pre-#754 fix this returned []; post-fix it resolves.
        let candidates = try await idx.resolveSymbolURIs(title: root.name)
        await idx.disconnect()

        #expect(candidates.count == 1, "Expected 1 candidate for \(root.name); got \(candidates.count)")
        try #require(candidates.first?.uri == root.uri)
        // Stored title is returned as-is (with the suffix); the resolver only normalises for matching.
        #expect(candidates.first?.title == suffixedTitle)
    }

    // MARK: - Bare-title shape (regression guard — must still work)

    @Test(
        "resolveSymbolURIs still finds canonical root types whose stored title is the bare form",
        arguments: canonicalRoots
    )
    func resolveBareTitleShape(root: (name: String, uri: String, framework: String)) async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)

        // Seed with the BARE form (no suffix) — the pre-#754-fix happy path.
        try await Self.indexSymbol(
            idx,
            uri: root.uri,
            framework: root.framework,
            storedTitle: root.name
        )

        let candidates = try await idx.resolveSymbolURIs(title: root.name)
        await idx.disconnect()

        #expect(candidates.count == 1, "Expected 1 candidate for \(root.name); got \(candidates.count)")
        try #require(candidates.first?.uri == root.uri)
        #expect(candidates.first?.title == root.name)
    }

    // MARK: - Mixed-shape disambiguation (both shapes seeded → both returned)

    @Test("resolveSymbolURIs returns both shapes when corpus has the symbol under suffixed AND bare forms")
    func resolveMixedShapes() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)

        // Real-world: NSObject exists under apple-docs://objectivec/nsobject-swift.class
        // with the suffixed title. Imagine a future ObjC port keeps the same name under
        // a different URI with the bare title. The resolver should return both.
        try await Self.indexSymbol(
            idx,
            uri: "apple-docs://objectivec/nsobject-swift.class",
            framework: "objectivec",
            storedTitle: "NSObject | Apple Developer Documentation"
        )
        try await Self.indexSymbol(
            idx,
            uri: "apple-docs://foundation/nsobject",
            framework: "foundation",
            storedTitle: "NSObject"
        )

        let candidates = try await idx.resolveSymbolURIs(title: "NSObject")
        await idx.disconnect()

        // ORDER BY framework in the resolver: foundation < objectivec alphabetically.
        #expect(candidates.count == 2, "Both shapes should resolve; got \(candidates.count)")
        let frameworks = candidates.map(\.framework).sorted()
        #expect(frameworks == ["foundation", "objectivec"])
    }

    // MARK: - Case-insensitive (existing behaviour, regression guard)

    @Test("resolveSymbolURIs stays case-insensitive on the user-supplied name")
    func resolveCaseInsensitive() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
        try await Self.indexSymbol(
            idx,
            uri: "apple-docs://objectivec/nsobject-swift.class",
            framework: "objectivec",
            storedTitle: "NSObject | Apple Developer Documentation"
        )

        // User types the symbol in different casings; all should resolve to the same row.
        for typed in ["NSObject", "nsobject", "NSOBJECT", "NsObject"] {
            let candidates = try await idx.resolveSymbolURIs(title: typed)
            #expect(candidates.count == 1, "typed=\(typed) returned \(candidates.count) candidates")
            #expect(candidates.first?.uri == "apple-docs://objectivec/nsobject-swift.class")
        }
        await idx.disconnect()
    }

    // MARK: - No match (regression guard — must still return empty cleanly)

    @Test("resolveSymbolURIs returns empty for unknown symbols (no false matches from suffix strip)")
    func resolveUnknownReturnsEmpty() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
        try await Self.indexSymbol(
            idx,
            uri: "apple-docs://uikit/uiview",
            framework: "uikit",
            storedTitle: "UIView"
        )

        let candidates = try await idx.resolveSymbolURIs(title: "NonexistentSymbolNobodyShouldHaveAdded")
        await idx.disconnect()

        #expect(candidates.isEmpty)
    }
}
