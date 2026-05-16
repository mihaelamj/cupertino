import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SharedConstants
import SQLite3
import Testing

/// Regression suite for [#669](https://github.com/mihaelamj/cupertino/issues/669) —
/// inheritance fallback that re-derives `inheritsFromURIs` and
/// `inheritedByURIs` from `StructuredDocumentationPage.rawMarkdown` when the
/// dedicated arrays are nil on a stale corpus.
///
/// The v1.2.0 bundle exposed the gap: the on-disk apple-docs JSON corpus
/// was crawled on 2026-05-09, a week before PR #638 added the URI second-walk
/// to `Core.JSONParser.AppleJSONToMarkdown.toStructuredPage`. The indexer reads
/// the saved `StructuredDocumentationPage` JSON straight from disk (see
/// `Search.Strategies.AppleDocs.swift:174-176`) — it doesn't re-run the
/// extractor — so the URI arrays decoded as nil and `writeInheritanceEdges`
/// produced zero rows for the entire bundle.
///
/// This suite locks in the defensive parser at
/// `Search.Index.extractInheritanceURIsFromMarkdown(_:)` that recovers
/// the same URIs from the page's preserved markdown blob, so any bundle
/// whose JSON predates #638 can be repaired with `cupertino save` alone.
@Suite("#669 inheritance fallback parser (rawMarkdown -> inheritance URIs)")
struct Issue669InheritanceFromMarkdownTests {
    @Test("UIButton: Inherits From -> UIControl")
    func uibuttonInheritsFromUIControl() {
        let markdown = """
        ## Topics

        ### [Buttons](/documentation/uikit/uibutton/buttons)

        ## [Relationships](/documentation/uikit/uibutton#relationships)

        ### [Inherits From](/documentation/uikit/uibutton#inherits-from)

        - [`UIControl`](/documentation/uikit/uicontrol)

        ### [Conforms To](/documentation/uikit/uibutton#conforms-to)

        - [`CALayerDelegate`](/documentation/QuartzCore/CALayerDelegate)

        - [`CVarArg`](/documentation/Swift/CVarArg)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://uikit/uicontrol"])
        #expect(result.inheritedBy.isEmpty)
    }

    @Test("UIControl: Inherited By -> multiple UIKit classes")
    func uicontrolInheritedByMultipleClasses() {
        let markdown = """
        ## [Relationships](/documentation/uikit/uicontrol#relationships)

        ### [Inherits From](/documentation/uikit/uicontrol#inherits-from)

        - [`UIView`](/documentation/uikit/uiview)

        ### [Inherited By](/documentation/uikit/uicontrol#inherited-by)

        - [`UIButton`](/documentation/uikit/uibutton)

        - [`UIDatePicker`](/documentation/uikit/uidatepicker)

        - [`UIPageControl`](/documentation/uikit/uipagecontrol)

        - [`UISegmentedControl`](/documentation/uikit/uisegmentedcontrol)

        - [`UISlider`](/documentation/uikit/uislider)

        - [`UIStepper`](/documentation/uikit/uistepper)

        - [`UISwitch`](/documentation/uikit/uiswitch)

        - [`UITextField`](/documentation/uikit/uitextfield)

        ### [Conforms To](/documentation/uikit/uicontrol#conforms-to)

        - [`UIAccessibility`](/documentation/uikit/uiaccessibility)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://uikit/uiview"])
        #expect(result.inheritedBy == [
            "apple-docs://uikit/uibutton",
            "apple-docs://uikit/uidatepicker",
            "apple-docs://uikit/uipagecontrol",
            "apple-docs://uikit/uisegmentedcontrol",
            "apple-docs://uikit/uislider",
            "apple-docs://uikit/uistepper",
            "apple-docs://uikit/uiswitch",
            "apple-docs://uikit/uitextfield",
        ])
    }

    @Test("absolute URLs in link targets resolve")
    func absoluteLinkTargetsResolve() {
        let markdown = """
        ### [Inherits From](https://developer.apple.com/documentation/foundation/nsobject#inherits-from)

        - [`NSObject`](https://developer.apple.com/documentation/objectivec/nsobject)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://objectivec/nsobject"])
    }

    @Test("plain heading without bracketed anchor still matches")
    func plainHeadingMatches() {
        let markdown = """
        ### Inherits From

        - [`UIResponder`](/documentation/uikit/uiresponder)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://uikit/uiresponder"])
    }

    @Test("missing sections return empty arrays")
    func missingSectionsReturnEmpty() {
        let markdown = """
        # SomeArticle

        ## Overview

        Some prose about a topic with no class relationships.

        ## Topics

        ### Subgroup A

        - [`SomeFunction()`](/documentation/swift/somefunction)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom.isEmpty)
        #expect(result.inheritedBy.isEmpty)
    }

    @Test("section with zero bullet items returns empty without crashing")
    func emptySectionReturnsEmpty() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        ### [Conforms To](/documentation/foo#conforms-to)

        - [`Sendable`](/documentation/Swift/Sendable)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom.isEmpty)
    }

    @Test("fragment-only links are skipped")
    func fragmentLinksAreSkipped() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`#section`](#section)

        - [`UIControl`](/documentation/uikit/uicontrol)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://uikit/uicontrol"])
    }

    @Test("non-Apple host links are skipped")
    func nonAppleHostLinksAreSkipped() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`External`](https://example.com/some/path)

        - [`UIControl`](/documentation/uikit/uicontrol)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://uikit/uicontrol"])
    }

    @Test("bullets continue across single blank lines (Apple's emit shape)")
    func bulletsContinueAcrossSingleBlanks() {
        // Apple emits one blank line between consecutive bullet items in
        // the relationships section. The parser must not stop at the
        // first blank.
        let markdown = """
        ### [Inherited By](/documentation/foo#inherited-by)

        - [`A`](/documentation/foo/a)

        - [`B`](/documentation/foo/b)

        - [`C`](/documentation/foo/c)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritedBy == [
            "apple-docs://foo/a",
            "apple-docs://foo/b",
            "apple-docs://foo/c",
        ])
    }

    @Test("case insensitive section title match")
    func caseInsensitiveSectionTitle() {
        let markdown = """
        ### [inherits from](/documentation/foo#inherits-from)

        - [`X`](/documentation/foo/x)
        """

        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/x"])
    }

    // MARK: - End-to-end indexer fallback

    /// Live wiring test: feed `indexStructuredDocument` a `StructuredDocumentationPage`
    /// shaped like the v1.2.0 stale corpus (nil `inheritsFromURIs`, nil
    /// `inheritedByURIs`, populated `rawMarkdown`) and confirm the
    /// `inheritance` table picks up the edges. This is the exact path
    /// `Search.Strategies.AppleDocs.swift` takes when decoding pre-#638
    /// JSON files from disk.
    @Test("indexStructuredDocument with stale page (nil URIs, populated rawMarkdown) writes edges via fallback")
    func staleIndexerWritesEdgesViaFallback() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue669-fallback-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Shape: pre-#638 JSON. The crawler-generated rawMarkdown carries
        // the relationship sections verbatim; the dedicated URI arrays
        // were never written.
        let rawMarkdown = """
        ---
        source: https://developer.apple.com/documentation/uikit/uibutton
        kind: class
        ---

        # UIButton

        ## [Relationships](/documentation/uikit/uibutton#relationships)

        ### [Inherits From](/documentation/uikit/uibutton#inherits-from)

        - [`UIControl`](/documentation/uikit/uicontrol)

        ### [Conforms To](/documentation/uikit/uibutton#conforms-to)

        - [`CALayerDelegate`](/documentation/QuartzCore/CALayerDelegate)
        """
        let page = try Shared.Models.StructuredDocumentationPage(
            url: #require(URL(string: "https://developer.apple.com/documentation/uikit/uibutton")),
            title: "UIButton",
            kind: .class,
            source: .appleJSON,
            inheritsFrom: nil,
            inheritsFromURIs: nil,
            inheritedByURIs: nil,
            rawMarkdown: rawMarkdown,
            contentHash: "test-hash"
        )

        try await idx.indexStructuredDocument(
            uri: "apple-docs://uikit/uibutton",
            source: "apple-docs",
            framework: "uikit",
            page: page,
            jsonData: "{}"
        )
        await idx.disconnect()

        let count = try Self.edgeCount(
            at: dbPath,
            parent: "apple-docs://uikit/uicontrol",
            child: "apple-docs://uikit/uibutton"
        )
        #expect(count == 1, "fallback parser should have written UIControl → UIButton edge from rawMarkdown")
    }

    /// When the dedicated URI arrays ARE populated (fresh post-#638 crawl),
    /// the fallback must not re-derive a competing edge set from
    /// rawMarkdown — the parser is authoritative. The test inserts a
    /// page where the dedicated array says one thing and the rawMarkdown
    /// says another; the dedicated array wins.
    @Test("indexStructuredDocument with populated URIs ignores rawMarkdown fallback")
    func populatedURIsBypassFallback() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue669-bypass-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // rawMarkdown says UIControl, dedicated arrays say UIResponder.
        // Dedicated arrays must win.
        let rawMarkdown = """
        ### [Inherits From](/documentation/uikit/uibutton#inherits-from)

        - [`UIControl`](/documentation/uikit/uicontrol)
        """
        let page = try Shared.Models.StructuredDocumentationPage(
            url: #require(URL(string: "https://developer.apple.com/documentation/uikit/uibutton")),
            title: "UIButton",
            kind: .class,
            source: .appleJSON,
            inheritsFrom: ["UIResponder"],
            inheritsFromURIs: ["apple-docs://uikit/uiresponder"],
            inheritedByURIs: nil,
            rawMarkdown: rawMarkdown,
            contentHash: "test-hash"
        )

        try await idx.indexStructuredDocument(
            uri: "apple-docs://uikit/uibutton",
            source: "apple-docs",
            framework: "uikit",
            page: page,
            jsonData: "{}"
        )
        await idx.disconnect()

        let responderEdge = try Self.edgeCount(
            at: dbPath,
            parent: "apple-docs://uikit/uiresponder",
            child: "apple-docs://uikit/uibutton"
        )
        let controlEdge = try Self.edgeCount(
            at: dbPath,
            parent: "apple-docs://uikit/uicontrol",
            child: "apple-docs://uikit/uibutton"
        )
        #expect(responderEdge == 1, "dedicated array's edge should be written")
        #expect(controlEdge == 0, "fallback must not double-fire when dedicated arrays are populated")
    }

    private static func edgeCount(at dbURL: URL, parent: String, child: String) throws -> Int {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw NSError(domain: "TestRead", code: 1)
        }
        let sql = "SELECT COUNT(*) FROM inheritance WHERE parent_uri = ? AND child_uri = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_text(stmt, 1, (parent as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (child as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }
}
