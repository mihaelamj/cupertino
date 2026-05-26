@testable import CoreJSONParser
import CoreProtocols
import Foundation
import Testing

/// Regression suite for [#614](https://github.com/mihaelamj/cupertino/issues/614).
///
/// Pre-fix, `MarkdownToStructuredPage.extractKind` first-matched the
/// `"<kind># <name>"` line pattern. Pages whose markdown rendered
/// conformance listings (`Protocol# Equatable`, `Protocol# Hashable`, …)
/// **before** the page's own heading (`Structure# String`) returned
/// `.protocol` instead of `.struct`. Hit canonical Swift stdlib types
/// — String, Array — and the typealias `Codable` (rendered as the
/// first-listed Article# heading).
///
/// Post-fix, the extractor takes the page title and prefers the line
/// whose suffix matches the title. First-match remains as a fallback
/// for pages where no exact-title heading exists.
@Suite("MarkdownToStructuredPage kind extraction (#614 title-anchored)")
struct MarkdownToStructuredPageKindExtractionTests {
    // MARK: - The bug class: conformance lines render before the main heading

    @Test("String page: 'Protocol# Equatable' precedes 'Structure# String' → returns .struct, not .protocol")
    func conformanceBeforeHeadingStruct() {
        let markdown = """
        ---
        title: String
        source: https://developer.apple.com/documentation/swift/string
        ---

        # String

        Protocol# Equatable
        Protocol# Hashable
        Protocol# Comparable
        Structure# String

        A Unicode string value that is a collection of characters.

        ```swift
        @frozen struct String
        ```
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        #expect(page != nil)
        #expect(page?.title == "String")
        #expect(page?.kind == .struct, "kind should resolve to .struct via the title-anchored match, not .protocol from the first conformance row")
    }

    @Test("Array page with multiple leading conformances → returns .struct")
    func arrayMultipleConformances() {
        let markdown = """
        ---
        title: Array
        source: https://developer.apple.com/documentation/swift/array
        ---

        # Array

        Protocol# Sequence
        Protocol# Collection
        Protocol# BidirectionalCollection
        Protocol# RandomAccessCollection
        Protocol# MutableCollection
        Protocol# RangeReplaceableCollection
        Structure# Array

        An ordered, random-access collection.

        ```swift
        @frozen struct Array<Element>
        ```
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        #expect(page?.kind == .struct)
    }

    @Test("Codable typealias page: 'Article# something' before 'Type Alias# Codable' → returns .typeAlias")
    func codableTypealias() {
        let markdown = """
        ---
        title: Codable
        source: https://developer.apple.com/documentation/swift/codable
        ---

        # Codable

        Article# Encoding and Decoding Custom Types
        Type Alias# Codable

        A type that can convert itself into and out of an external representation.

        ```swift
        typealias Codable = Decodable & Encodable
        ```
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        #expect(page?.kind == .typeAlias)
    }

    // MARK: - Regression anchors — must NOT tip the already-correct cases

    @Test("Task class page (no conformance noise): still resolves to .class")
    func taskClassUnchanged() {
        let markdown = """
        ---
        title: Task
        source: https://developer.apple.com/documentation/swift/task
        ---

        # Task

        Class# Task

        A unit of asynchronous work.

        ```swift
        final class Task<Success, Failure> where Failure: Error, Success: Sendable
        ```
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        #expect(page?.kind == .class)
    }

    @Test("View protocol page (genuine protocol): still resolves to .protocol")
    func viewProtocolUnchanged() {
        let markdown = """
        ---
        title: View
        source: https://developer.apple.com/documentation/swiftui/view
        ---

        # View

        Protocol# View

        A type that represents part of your app's user interface.

        ```swift
        protocol View
        ```
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        #expect(page?.kind == .protocol)
    }

    @Test("Hashable protocol page: leading conformance rows but title-anchored line says Protocol → .protocol")
    func hashableProtocolWithLeadingConformances() {
        let markdown = """
        ---
        title: Hashable
        source: https://developer.apple.com/documentation/swift/hashable
        ---

        # Hashable

        Protocol# Equatable
        Protocol# Hashable

        A type that can be hashed into a Hasher to produce an integer hash value.

        ```swift
        protocol Hashable: Equatable
        ```
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        // The title-anchored line is `Protocol# Hashable` (suffix = "Hashable" == title), so .protocol is correct.
        // Even without the fix, first-match would have hit `Protocol# Equatable` and (wrongly) returned .protocol;
        // the post-fix value happens to coincide. The anchor here is that the new code does NOT regress this case.
        #expect(page?.kind == .protocol)
    }

    // MARK: - Fallback behaviour

    @Test("Page where no heading suffix matches the title: falls back to first-match (pre-#614 behaviour)")
    func fallbackToFirstMatch() {
        // Title is "Mystery" but no `<Kind># Mystery` line exists.
        // Pre-#614 would have returned the first matching kind line; post-#614
        // also returns that (via the fallback pass) — no regression to .unknown.
        let markdown = """
        ---
        title: Mystery
        source: https://developer.apple.com/documentation/swift/mystery
        ---

        # Mystery

        Function# helperOne()
        Function# helperTwo()

        Some documentation.
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        #expect(page?.kind == .function)
    }

    @Test("Page with no Kind# lines at all → .unknown")
    func noKindLinesReturnsUnknown() {
        let markdown = """
        ---
        title: SomeArticle
        source: https://developer.apple.com/documentation/somewhere
        ---

        # SomeArticle

        Just an article. No `Kind# Title` line.
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        #expect(page?.kind == .unknown)
    }

    // MARK: - Edge cases

    @Test("Whitespace tolerance: 'Structure  #  String' (extra spaces) still matches when title is 'String'")
    func whitespaceTolerantSuffixMatch() {
        let markdown = """
        ---
        title: String
        source: https://developer.apple.com/documentation/swift/string
        ---

        # String

        Protocol# Equatable
        Structure  #  String

        Body.

        ```swift
        @frozen struct String
        ```
        """

        let page = Core.JSONParser.MarkdownToStructuredPage.convert(markdown)
        #expect(page?.kind == .struct)
    }
}
