import Foundation
@testable import Search
import Testing

// MARK: - #113 — `doc://` → `https://` link rewriter (pure-function contract)

//
// Apple's DocC renderer is supposed to translate internal
// `doc://<bundleID>/documentation/<framework>/<path>` URIs to public
// `https://developer.apple.com/documentation/<framework>/<path>` URLs
// before serving the HTML pages cupertino crawls. The translation
// sometimes fails — raw `doc://` URIs leak through the renderer and
// land in stored content, where AI clients hit unfollowable refs.
//
// Per the #113 decision: index-time rewrite (Option 1), total rewrite
// policy, edge-case (a) for unresolved targets (rewrite anyway — the
// public URL is valid even when cupertino didn't index the target).
//
// This file pins the pure-function rewriter contract; the indexer
// wiring + post-save invariant are in `Issue113IndexerRewriteIntegrationTests`.

@Suite("#113 — DocLinkRewriter pure-function contract", .serialized)
struct Issue113DocLinkRewriterTests {
    // MARK: - 1. Standard path

    @Test("standard path: doc://X/documentation/foo/bar → https://developer.apple.com/documentation/foo/bar")
    func standardPath() {
        let input = "See doc://X/documentation/foo/bar for details."
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == "See https://developer.apple.com/documentation/foo/bar for details.")
        #expect(count == 1)
    }

    @Test("canonical Apple bundle id: doc://com.apple.documentation/documentation/swiftui/view → public URL")
    func canonicalAppleBundleId() {
        let input = "doc://com.apple.documentation/documentation/swiftui/view"
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == "https://developer.apple.com/documentation/swiftui/view")
        #expect(count == 1)
    }

    // MARK: - 2. Anchor / fragment preservation

    @Test("anchor preserved: ...#fragment passes through")
    func anchorPreserved() {
        let input = "doc://X/documentation/foo/bar#initialization"
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == "https://developer.apple.com/documentation/foo/bar#initialization")
        #expect(count == 1)
    }

    // MARK: - 3. Multi-segment path

    @Test("multi-segment path with hash-suffix preserved")
    func multiSegmentPath() {
        let input = "doc://com.apple.documentation/documentation/swiftui/view/init(_:)-abc12"
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == "https://developer.apple.com/documentation/swiftui/view/init(_:)-abc12")
        #expect(count == 1)
    }

    // MARK: - 4. Bundle-id agnostic

    @Test(
        "rewriter doesn't care which bundle id appears between doc:// and /documentation/",
        arguments: [
            "doc://com.apple.documentation/documentation/foo/bar",
            "doc://com.apple.swiftui/documentation/foo/bar",
            "doc://anything/documentation/foo/bar",
            "doc://X/documentation/foo/bar",
            "doc://2c3d4e/documentation/foo/bar",
        ]
    )
    func bundleIdAgnostic(input: String) {
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == "https://developer.apple.com/documentation/foo/bar")
        #expect(count == 1)
    }

    // MARK: - 5. Mixed content + multiple occurrences

    @Test("prose surrounding the link is preserved verbatim")
    func proseSurroundingPreserved() {
        let input = "Lorem ipsum doc://X/documentation/swiftui/view dolor sit amet."
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == "Lorem ipsum https://developer.apple.com/documentation/swiftui/view dolor sit amet.")
        #expect(count == 1)
    }

    @Test("multiple doc:// in one input: all rewritten + count matches")
    func multipleOccurrences() {
        let input = """
        First: doc://X/documentation/foo/a.
        Second: doc://X/documentation/foo/b.
        Third: doc://X/documentation/foo/c.
        """
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(count == 3)
        #expect(output.contains("https://developer.apple.com/documentation/foo/a"))
        #expect(output.contains("https://developer.apple.com/documentation/foo/b"))
        #expect(output.contains("https://developer.apple.com/documentation/foo/c"))
        #expect(!output.contains("doc://"), "post-rewrite output must not retain any doc:// — got: \(output)")
    }

    // MARK: - 6. Idempotency

    @Test("running rewrite twice == running rewrite once (idempotent on real links)")
    func idempotent() {
        let input = "doc://X/documentation/swiftui/view and doc://Y/documentation/uikit/uibutton"
        let (firstOutput, firstCount) = DocLinkRewriter.rewrite(input)
        let (secondOutput, secondCount) = DocLinkRewriter.rewrite(firstOutput)
        #expect(firstOutput == secondOutput, "second pass should be a no-op; got: \(secondOutput)")
        #expect(firstCount == 2)
        #expect(secondCount == 0, "second pass must report zero substitutions; got: \(secondCount)")
    }

    // MARK: - 7. No-match short-circuit

    @Test("no doc:// substring: input returned identical + count 0")
    func noMatch() {
        let input = "Plain prose with https://developer.apple.com/documentation/swiftui/view embedded."
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == input)
        #expect(count == 0)
    }

    @Test("empty input")
    func emptyInput() {
        let (output, count) = DocLinkRewriter.rewrite("")
        #expect(output == "")
        #expect(count == 0)
    }

    // MARK: - 8. doc:// without /documentation/ anchor

    @Test("doc:// without /documentation/: preserved verbatim, count 0")
    func docSchemeWithoutDocumentationAnchor() {
        // Some prose / quoted examples have raw doc:// text that doesn't
        // point at a DocC documentation page. The rewriter must not
        // mangle these — they're literally just text.
        let input = "Apple's internal scheme is doc://com.apple.unrelated/topic/foo."
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == input)
        #expect(count == 0)
    }

    // MARK: - 9. URL terminators

    @Test(
        "scan stops at characters that conventionally terminate a URL in surrounding markup",
        arguments: [
            ("(doc://X/documentation/foo/bar)", "(https://developer.apple.com/documentation/foo/bar)"),
            ("[doc://X/documentation/foo/bar]", "[https://developer.apple.com/documentation/foo/bar]"),
            ("<doc://X/documentation/foo/bar>", "<https://developer.apple.com/documentation/foo/bar>"),
            ("\"doc://X/documentation/foo/bar\"", "\"https://developer.apple.com/documentation/foo/bar\""),
            ("`doc://X/documentation/foo/bar`", "`https://developer.apple.com/documentation/foo/bar`"),
        ]
    )
    func urlTerminators(input: String, expected: String) {
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == expected, "expected \(expected), got: \(output)")
        #expect(count == 1)
    }

    @Test("whitespace terminates the URL scan")
    func whitespaceTerminator() {
        let input = "Link: doc://X/documentation/foo/bar more text here"
        let (output, count) = DocLinkRewriter.rewrite(input)
        #expect(output == "Link: https://developer.apple.com/documentation/foo/bar more text here")
        #expect(count == 1)
    }

    // MARK: - 10. JSON safety

    @Test("rewriting inside a serialised JSON doc preserves JSON structure")
    func jsonSafety() throws {
        let json = #"{"links":["doc://X/documentation/foo/a","doc://Y/documentation/bar/b"],"title":"Hello"}"#
        let (output, count) = DocLinkRewriter.rewrite(json)
        #expect(count == 2)

        // Must still parse as JSON post-rewrite.
        let parsed = try JSONSerialization.jsonObject(with: Data(output.utf8))
        let dict = try #require(parsed as? [String: Any])
        let links = try #require(dict["links"] as? [String])
        #expect(links == [
            "https://developer.apple.com/documentation/foo/a",
            "https://developer.apple.com/documentation/bar/b",
        ])
        #expect(dict["title"] as? String == "Hello")
    }

    // MARK: - 11. Total-rewrite invariant

    @Test("no doc:// remains in the output for any standard input")
    func totalRewriteInvariant() {
        let inputs = [
            "doc://X/documentation/a",
            "(doc://X/documentation/b)",
            "doc://X/documentation/c then doc://Y/documentation/d",
            #"{"k":"doc://X/documentation/e"}"#,
            "Plain doc://com.apple.documentation/documentation/foo/bar text",
        ]
        for input in inputs {
            let (output, _) = DocLinkRewriter.rewrite(input)
            #expect(
                !output.contains("doc://com.apple.documentation/documentation/"),
                "doc:// scheme must be fully rewritten in '\(input)' — got: \(output)"
            )
        }
    }

    // MARK: - 12. Count audit

    @Test("count equals exact number of substitutions")
    func countAudit() {
        let zero = DocLinkRewriter.rewrite("no links here")
        #expect(zero.count == 0)

        let one = DocLinkRewriter.rewrite("doc://X/documentation/foo/a")
        #expect(one.count == 1)

        let five = DocLinkRewriter.rewrite(
            "doc://X/documentation/a doc://X/documentation/b " +
                "doc://X/documentation/c doc://X/documentation/d " +
                "doc://X/documentation/e"
        )
        #expect(five.count == 5)
    }
}
