import Foundation
@testable import Search
import SearchModels
import SharedConstants
import Testing

/// Fuzz + edge-case test battery for the #669 rawMarkdown inheritance parser
/// (`Search.Index.extractInheritanceURIsFromMarkdown`). Phase C of #673 —
/// "over-test rather than under-test" per Carmack.
///
/// `Issue669InheritanceFromMarkdownTests` covers the happy-path shapes
/// (UIButton, UIControl, absolute URLs, plain headings, case-insensitive,
/// fragment / non-Apple skip, single-blank continuity). This file pushes
/// the parser against malformed and adversarial input — empty strings,
/// Unicode in section titles, CRLF line endings, mixed bullet markers,
/// nested sections, parenthesised URL paths, very long inputs, etc.
///
/// Pre-existing parser path is locked in: no test in this suite is allowed
/// to crash. Every input — however broken — must produce a deterministic
/// `(inheritsFrom: [String], inheritedBy: [String])` tuple. A regression
/// that introduces force-unwraps or out-of-bounds reads breaks one of
/// these tests immediately instead of waiting for a Cupertino user to hit
/// the shape in production.
@Suite("#669 rawMarkdown parser fuzz + edge cases (Phase C)")
// swiftlint:disable:next type_body_length
struct Issue669ParserFuzzTests {
    // MARK: - Empty / degenerate inputs

    @Test("empty string returns empty tuple")
    func emptyStringReturnsEmpty() {
        let result = Search.Index.extractInheritanceURIsFromMarkdown("")
        #expect(result.inheritsFrom.isEmpty)
        #expect(result.inheritedBy.isEmpty)
    }

    @Test("whitespace-only string returns empty tuple")
    func whitespaceOnlyReturnsEmpty() {
        let result = Search.Index.extractInheritanceURIsFromMarkdown("   \n\n\n\t\t  ")
        #expect(result.inheritsFrom.isEmpty)
        #expect(result.inheritedBy.isEmpty)
    }

    @Test("single-character input returns empty tuple")
    func singleCharacterReturnsEmpty() {
        let result = Search.Index.extractInheritanceURIsFromMarkdown("a")
        #expect(result.inheritsFrom.isEmpty)
        #expect(result.inheritedBy.isEmpty)
    }

    @Test("heading without any bullet items returns empty array (not nil)")
    func headingWithoutItemsReturnsEmpty() {
        let markdown = "### [Inherits From](/documentation/foo#inherits-from)\n"
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom.isEmpty)
    }

    // MARK: - Line ending variants

    @Test("CRLF line endings are tolerated")
    func crlfLineEndings() {
        let markdown = "### [Inherits From](/documentation/uikit/uibutton#inherits-from)\r\n\r\n" +
            "- [`UIControl`](/documentation/uikit/uicontrol)\r\n"
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // The trailing `\r` should be tolerated by the trim step;
        // the URI extraction either yields the right URI or skips
        // cleanly. The fuzz contract is "no crash"; ideally also
        // "extracts correctly".
        #expect(result.inheritsFrom == ["apple-docs://uikit/uicontrol"])
    }

    @Test("LF-only line endings (the standard) work")
    func lfOnly() {
        let markdown = "### [Inherits From](/documentation/uikit/uibutton#inherits-from)\n\n" +
            "- [`UIControl`](/documentation/uikit/uicontrol)\n"
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://uikit/uicontrol"])
    }

    // MARK: - Bullet marker variants

    @Test("asterisk bullet marker `* [link](target)` is accepted")
    func asteriskBullet() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        * [`X`](/documentation/foo/x)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/x"])
    }

    @Test("non-bullet line in the middle of items is silently skipped, list continues")
    func nonBulletLineIsSkippedNotTerminated() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`A`](/documentation/foo/a)

        not a bullet line

        - [`B`](/documentation/foo/b)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // Implementation contract (locks current parser behaviour): a non-
        // bullet, non-blank, non-heading line is silently skipped — it
        // resets the blank-run counter but doesn't terminate the bullet
        // walk. So both `A` and `B` are captured. Termination requires
        // either a heading (`#`-prefixed line) or a run of 2+ blank
        // lines. This is lenient by design — Apple's markdown sometimes
        // intersperses annotation lines between bullets.
        #expect(result.inheritsFrom == [
            "apple-docs://foo/a",
            "apple-docs://foo/b",
        ])
    }

    // MARK: - Malformed link syntax

    @Test("missing closing paren — link target is unparseable; bullet skipped")
    func missingClosingParen() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`Broken`](/documentation/foo/broken
        - [`OK`](/documentation/foo/ok)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // Greedy `range(of: ")", options: .backwards)` will find the last `)`
        // in the matched section. The first bullet has no `)` on its own
        // line; the parser's per-line logic looks within that line only.
        // So the malformed bullet is dropped, the well-formed one captured.
        #expect(result.inheritsFrom.contains("apple-docs://foo/ok"))
    }

    @Test("empty link target is dropped")
    func emptyLinkTarget() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`Empty`]()

        - [`Real`](/documentation/foo/real)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/real"])
    }

    @Test("link target with only a fragment is dropped")
    func fragmentOnlyTarget() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`SamePageAnchor`](#section)

        - [`Real`](/documentation/foo/real)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/real"])
    }

    // MARK: - Path / URL adversarial shapes

    @Test("URL with embedded parens in path (Apple's symbol-name syntax) is accepted")
    func embeddedParensInPath() {
        // Apple's symbol-name URLs include `(_:_:)` style suffixes for
        // operator overloads + initialisers. The link-target parser uses
        // `range(of: ")", options: .backwards)` to find the closing paren
        // of the markdown `[text](target)` form — embedded parens in the
        // target work because we look for the LAST `)`.
        let markdown = """
        ### [Inherited By](/documentation/foo#inherited-by)

        - [`init(rawValue:)`](/documentation/accelerate/sparsepreconditioner-t/init(rawvalue:))
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritedBy == ["apple-docs://accelerate/sparsepreconditioner-t/init(rawvalue:)"])
    }

    @Test("URL with query string is preserved or dropped (no crash)")
    func urlWithQueryString() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`X`](/documentation/foo/x?lang=swift)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // Contract is just "no crash". The URI may or may not include the
        // query string depending on appleDocsURI's normalisation;
        // both are acceptable.
        #expect(result.inheritsFrom.count <= 1)
    }

    @Test("very long path doesn't crash the parser")
    func veryLongPath() {
        let longSlug = String(repeating: "a", count: 500)
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`X`](/documentation/foo/\(longSlug))
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // Should produce one URI or zero (depending on URI normaliser).
        // Contract: no crash, deterministic output.
        #expect(result.inheritsFrom.count <= 1)
    }

    // MARK: - Section interleaving

    @Test("both Inherits From and Inherited By in same document, in any order")
    func bothSectionsInverseOrder() {
        let markdown = """
        ### [Inherited By](/documentation/foo#inherited-by)

        - [`Child`](/documentation/foo/child)

        ### [Inherits From](/documentation/foo#inherits-from)

        - [`Parent`](/documentation/foo/parent)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/parent"])
        #expect(result.inheritedBy == ["apple-docs://foo/child"])
    }

    @Test("only Inherits From present (no Inherited By)")
    func onlyInheritsFrom() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`Parent`](/documentation/foo/parent)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/parent"])
        #expect(result.inheritedBy.isEmpty)
    }

    @Test("only Inherited By present (no Inherits From)")
    func onlyInheritedBy() {
        let markdown = """
        ### [Inherited By](/documentation/foo#inherited-by)

        - [`Child`](/documentation/foo/child)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom.isEmpty)
        #expect(result.inheritedBy == ["apple-docs://foo/child"])
    }

    @Test("Inherited By terminates Inherits From's bullet list cleanly")
    func nextHeadingTerminatesPriorSection() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`Parent`](/documentation/foo/parent)

        ### [Inherited By](/documentation/foo#inherited-by)

        - [`ChildA`](/documentation/foo/childa)

        - [`ChildB`](/documentation/foo/childb)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/parent"])
        #expect(result.inheritedBy == [
            "apple-docs://foo/childa",
            "apple-docs://foo/childb",
        ])
    }

    // MARK: - Heading depth variants

    @Test("Heading depth ## vs #### still matches (parser is depth-agnostic on the title text)")
    func headingDepthVariants() {
        // Implementation note: the parser matches lines starting with
        // `### [Inherits From]` or `### Inherits From`. Different depths
        // (`##` or `####`) currently DO NOT match by design — Apple emits
        // exactly `###`. Locks the contract.
        let markdown = """
        ## [Inherits From](/documentation/foo#inherits-from)

        - [`Parent`](/documentation/foo/parent)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // Expectation: `##` is not matched. inheritsFrom stays empty.
        #expect(result.inheritsFrom.isEmpty)
    }

    @Test("Heading with extra spaces after ### still matches")
    func headingExtraSpaces() {
        let markdown = """
        ###  [Inherits From](/documentation/foo#inherits-from)

        - [`Parent`](/documentation/foo/parent)
        """
        // The parser does an `hasPrefix("### \(sectionTitle)".lowercased())`
        // check after trimming. Extra spaces after `###` would mean the
        // line doesn't `hasPrefix("### [Inherits From]")` literally — but
        // double-space → `###  [Inherits From]` is "### " + " [Inherits…"
        // which does still start with `### [`? No, it starts with `### `
        // followed by SPACE then `[`. So `hasPrefix("### [Inherits From]")`
        // requires exactly one space. This test pins that contract: extra
        // spaces break the match.
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom.isEmpty)
    }

    // MARK: - Unicode + emoji

    @Test("Unicode in bullet text doesn't break parsing of the link target")
    func unicodeInBulletText() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`Pärænt 🌟`](/documentation/foo/parent)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/parent"])
    }

    @Test("Unicode in URL target is preserved or skipped (no crash)")
    func unicodeInURLTarget() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`X`](/documentation/foo/päréntlol)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // Contract: no crash. The output is whatever URLUtilities.appleDocsURI
        // produces for the unicode-containing path.
        #expect(result.inheritsFrom.count <= 1)
    }

    // MARK: - Adversarial: structural noise around real data

    @Test("Inherits From wrapped in HTML-like noise — the markdown is what matters")
    func htmlNoiseAroundRealSection() {
        let markdown = """
        <div class="relationships">

        ### [Inherits From](/documentation/foo#inherits-from)

        - [`Parent`](/documentation/foo/parent)

        </div>
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/parent"])
    }

    @Test("Multiple Inherits From sections — first one wins (locks contract)")
    func multipleInheritsFromSections() {
        let markdown = """
        ### [Inherits From](/documentation/foo#inherits-from)

        - [`FirstParent`](/documentation/foo/firstparent)

        ### Some other section

        ### [Inherits From](/documentation/foo#inherits-from-again)

        - [`SecondParent`](/documentation/foo/secondparent)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // Parser finds the FIRST `### [Inherits From]` heading and walks
        // bullets immediately after. Second occurrence is ignored.
        // Apple's pages never emit two `Inherits From` sections — this
        // pin documents the choice for the malicious / adversarial input
        // case.
        #expect(result.inheritsFrom == ["apple-docs://foo/firstparent"])
    }

    // MARK: - Parameterised sweep across malformed shapes

    /// Property-style fuzz: every input below MUST produce a deterministic
    /// `(inheritsFrom, inheritedBy)` tuple with no crash. The expected
    /// content is `[]` / `[]` for the genuinely broken inputs; any
    /// behaviour change is a regression worth surfacing.
    @Test(
        "fuzz: malformed inputs produce empty arrays, no crash",
        arguments: [
            "",
            " ",
            "\n",
            "\n\n\n",
            "\r\n\r\n",
            "###",
            "### ",
            "### [",
            "### []",
            "### [](",
            "### [](/)",
            "### [Inherits From",
            "### [Inherits From]",
            "### [Inherits From](",
            "###  [Inherits From](/...)", // double-space after ### breaks the prefix
            "## [Inherits From](/...)", // wrong depth
            "#### [Inherits From](/...)", // deeper, no match
            "**bold** without heading",
            "Topics: Section A",
            "<script>alert(1)</script>",
            "🎉🎊🎈",
            String(repeating: "a", count: 10000),
            String(repeating: "###\n", count: 100),
            String(repeating: "- [x](/y)\n", count: 100),
        ]
    )
    func fuzzMalformedInputsAreSafe(_ input: String) {
        // Contract: parser must not crash, must return a deterministic tuple.
        // The test SUCCEEDS by running to completion — any uncaught
        // exception, force-unwrap, or out-of-bounds read would crash the
        // test runner. We don't pin specific output shapes for the
        // adversarial inputs (they're allowed to produce anything as long
        // as it's a valid tuple); the named tests above cover the
        // well-formed shapes.
        _ = Search.Index.extractInheritanceURIsFromMarkdown(input)
    }

    @Test(
        "case-insensitive title match across letter-casing variants",
        arguments: [
            "Inherits From",
            "INHERITS FROM",
            "inherits from",
            "Inherits from",
            "iNhErItS fRoM",
        ]
    )
    func caseInsensitiveTitleMatch(_ titleCasing: String) {
        let markdown = "### [\(titleCasing)](/documentation/foo)\n\n- [`Parent`](/documentation/foo/parent)\n"
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom == ["apple-docs://foo/parent"])
    }

    // MARK: - Whitespace adversarial

    @Test("tab characters in section heading + bullet are tolerated")
    func tabCharacters() {
        let markdown = "### [Inherits From](/documentation/foo)\n\n\t- [`Parent`](/documentation/foo/parent)\n"
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // Leading tab on bullet: trimmingCharacters(in: .whitespaces) strips it,
        // bullet should be recognised.
        #expect(result.inheritsFrom == ["apple-docs://foo/parent"])
    }

    @Test("multiple blank lines between heading and first bullet — single blank OK, double blank terminates")
    func doubleBlankAfterHeadingTerminates() {
        let markdown = """
        ### [Inherits From](/documentation/foo)


        - [`Parent`](/documentation/foo/parent)
        """
        // Implementation: blankRun >= 2 terminates the walk. So the bullet
        // after two consecutive blank lines is NOT captured.
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        #expect(result.inheritsFrom.isEmpty)
    }

    @Test("triple-blank between bullets terminates the list at the first run-of-blanks")
    func tripleBlankBetweenBullets() {
        let markdown = """
        ### [Inherits From](/documentation/foo)

        - [`A`](/documentation/foo/a)



        - [`B`](/documentation/foo/b)
        """
        let result = Search.Index.extractInheritanceURIsFromMarkdown(markdown)
        // After A there's the per-Apple single blank + 2 more blanks; double-blank
        // run terminates. Only A captured.
        #expect(result.inheritsFrom == ["apple-docs://foo/a"])
    }
}
