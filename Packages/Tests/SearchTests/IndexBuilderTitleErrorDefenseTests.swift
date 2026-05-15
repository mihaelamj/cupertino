import Foundation
@testable import Search
import SearchModels
import SharedConstants
import Testing

// Truth-table coverage for `Search.IndexBuilder.titleLooksLikeHTTPErrorTemplate`,
// the indexer-side defense added as a belt-and-suspenders to PR #289's
// crawler-side gate. Even if a poison JSON file lands on disk via mid-flight
// rsync, restored backup, or hand-edited corpus, the indexer must refuse to
// index it.
//
// The audit on the v1.0.2 bundle saw 23 × "403 Forbidden" + 45 × "502 Bad
// Gateway" rows; this defense would have caught all of them at index time.

@Suite("Search.IndexBuilder.titleLooksLikeHTTPErrorTemplate (#284 indexer defense)")
struct IndexBuilderTitleErrorDefenseTests {
    typealias SUT = Search.StrategyHelpers

    // MARK: status-prefix form

    @Test(
        "every spec'd status-prefix title trips the gate",
        arguments: [
            "403 Forbidden",
            "404 Not Found",
            "429 Too Many Requests",
            "500 Internal Server Error",
            "502 Bad Gateway",
            "503 Service Unavailable",
            "504 Gateway Timeout",
        ]
    )
    func statusPrefixTitlesAreDetected(title: String) {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate(title) == true)
    }

    @Test("status-prefix at end-of-string also trips (no trailing phrase)")
    func bareStatusCodeIsDetected() {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("502") == true)
    }

    // MARK: standalone phrase form

    @Test(
        "standalone error phrases trip the gate",
        arguments: [
            "Forbidden",
            "Bad Gateway",
            "Not Found",
            "Service Unavailable",
            "Gateway Timeout",
            "Too Many Requests",
            "Internal Server Error",
        ]
    )
    func standalonePhrasesAreDetected(title: String) {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate(title) == true)
    }

    @Test("standalone with whitespace trims correctly")
    func whitespaceTrimming() {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("  Bad Gateway  ") == true)
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("\n502 Bad Gateway\n") == true)
    }

    // MARK: real Apple titles MUST NOT trip

    @Test(
        "real Apple symbol titles must NOT be flagged",
        arguments: [
            "AVCustomMediaSelectionScheme",
            "withTaskGroup(of:returning:isolation:body:)",
            "UIDropOperation.forbidden", // contains "forbidden" but not standalone
            "MTRAccessControlAccessRestrictionType.attributeAccessForbidden",
            "AVError.Code.referenceForbiddenByReferencePolicy",
            "Routing404Type", // contains digits but not status prefix
            "callAsyncJavaScript(_:arguments:in:contentWorld:)",
            "GameCenterLeaderboardSetLocalization.Attributes",
            "Handling Bad Gateway responses in Apps and Books API", // legit doc that mentions phrase mid-sentence
            "Interpreting error codes (400, 401, 403)", // legit doc page about error codes
        ]
    )
    func realAppleTitlesAreNotFlagged(title: String) {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate(title) == false)
    }

    // MARK: degenerate inputs

    @Test("empty title returns false (handled by the existing missing-title guard)")
    func emptyTitleReturnsFalse() {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("") == false)
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("   ") == false)
    }

    @Test("status code without proper boundary is not flagged (e.g. '502abc')")
    func bareDigitsWithoutBoundaryAreNotFlagged() {
        // The regex requires a whitespace or end-of-string anchor after the
        // status code. "502abc" lacks that, so it's not flagged. Pinned so a
        // future loosening of the regex is a conscious decision.
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("502abc") == false)
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("404Type") == false)
    }
}

// MARK: - JS-disabled fallback page detection

// Coverage for `Search.IndexBuilder.pageLooksLikeJavaScriptFallback(_ page:)`,
// the second indexer-side defense added after the audit found 1,327 such
// poisoned files in the v1.0.2-era corpus that every prior title-only
// check missed. The poisoned page has a real-looking title (Apple ships
// it in HTML metadata even when JS is off) but the body content is
// `Please turn on JavaScript ...` with rawMarkdown `[ Skip Navigation
// ](#app-main)# An unknown error occurred.`.

@Suite("Search.IndexBuilder.pageLooksLikeJavaScriptFallback (#284 JS-fallback defense)")
struct IndexBuilderJavaScriptFallbackDefenseTests {
    typealias SUT = Search.StrategyHelpers

    private static func makePage(
        title: String = "AVCustomMediaSelectionScheme",
        kind: Shared.Models.StructuredDocumentationPage.Kind = .class,
        source: Shared.Models.StructuredDocumentationPage.Source = .appleJSON,
        overview: String? = nil,
        rawMarkdown: String? = nil
    ) -> Shared.Models.StructuredDocumentationPage {
        Shared.Models.StructuredDocumentationPage(
            url: try! URL(knownGood: "https://developer.apple.com/documentation/test"),
            title: title,
            kind: kind,
            source: source,
            overview: overview,
            rawMarkdown: rawMarkdown
        )
    }

    @Test("overview containing 'Please turn on JavaScript' trips the gate")
    func jsFallbackInOverviewIsDetected() {
        let page = Self.makePage(
            overview: "Please turn on JavaScript in your browser and refresh the page to view its content."
        )
        #expect(SUT.pageLooksLikeJavaScriptFallback(page) == true)
    }

    @Test("rawMarkdown containing 'Please turn on JavaScript' trips the gate")
    func jsFallbackInRawMarkdownIsDetected() {
        let page = Self.makePage(
            rawMarkdown: "---\nsource: x\n---\n\n# Title\n\nPlease turn on JavaScript and refresh."
        )
        #expect(SUT.pageLooksLikeJavaScriptFallback(page) == true)
    }

    @Test("rawMarkdown containing the broken Skip-Navigation pattern trips the gate")
    func skipNavigationBrokenBodyIsDetected() {
        let page = Self.makePage(
            rawMarkdown: "---\nsource: x\n---\n\n# Title\n\n[ Skip Navigation ](#app-main)# An unknown error occurred."
        )
        #expect(SUT.pageLooksLikeJavaScriptFallback(page) == true)
    }

    @Test("real Apple page with normal overview is NOT flagged")
    func realPageNotFlagged() {
        let page = Self.makePage(
            overview: "## Overview\n\nA media selection scheme provides custom settings for controlling media presentation."
        )
        #expect(SUT.pageLooksLikeJavaScriptFallback(page) == false)
    }

    @Test("real Apple page that mentions 'JavaScript' in normal docs context is NOT flagged")
    func realPageMentioningJavaScriptNotFlagged() {
        // Real Apple docs about WebKit / JavaScript APIs legitimately mention
        // the word JavaScript without being JS-disabled fallbacks. The check
        // requires the literal phrase "Please turn on JavaScript" — that
        // exact string is unique to the fallback template.
        let page = Self.makePage(
            title: "WKWebView.evaluateJavaScript",
            overview: "Use this method to execute JavaScript code in the context of the loaded page."
        )
        #expect(SUT.pageLooksLikeJavaScriptFallback(page) == false)
    }

    @Test("page with nil overview AND nil rawMarkdown is NOT flagged")
    func nilFieldsNotFlagged() {
        let page = Self.makePage(overview: nil, rawMarkdown: nil)
        #expect(SUT.pageLooksLikeJavaScriptFallback(page) == false)
    }

    @Test("page with empty-string overview AND empty rawMarkdown is NOT flagged")
    func emptyFieldsNotFlagged() {
        let page = Self.makePage(overview: "", rawMarkdown: "")
        #expect(SUT.pageLooksLikeJavaScriptFallback(page) == false)
    }
}

// MARK: - #588: placeholder-title defence

// Sister defence to the #284 HTTP-error gate above: catches the
// "Error" / "Apple Developer Documentation" / empty-string title
// patterns Apple's JS app emits when its data fetch fails after
// the page chrome was already painted. Found by the corpus audit
// in issue #588 (PDFKit pdfViewParentViewController, PHASE
// SoundEvent, others) — these slip past the HTTP-error gate
// because they don't carry an HTTP status code in the title.

@Suite("Search.StrategyHelpers.titleLooksLikePlaceholderError (#588 indexer defence)")
struct StrategyHelpersPlaceholderErrorDefenceTests {
    typealias SUT = Search.StrategyHelpers

    // MARK: - Placeholder titles that always trip the gate (no URL context needed)

    @Test(
        "empty / apple-developer-documentation placeholder shapes always trip the gate",
        arguments: [
            "Apple Developer Documentation",
            "apple developer documentation",
            "  Apple Developer Documentation\n",
            "",
            "   ",
            "\n\t  \n",
        ]
    )
    func unconditionalPlaceholderTitlesAreDetected(title: String) {
        // No URL — these patterns trip regardless of context.
        #expect(SUT.titleLooksLikePlaceholderError(title) == true)
        // With a URL — still trip.
        let anyURL = URL(string: "https://developer.apple.com/documentation/pdfkit/pdfviewdelegate/pdfviewparentviewcontroller()")!
        #expect(SUT.titleLooksLikePlaceholderError(title, url: anyURL) == true)
    }

    // MARK: - "Error" title needs URL context (corpus dry-run found
    //         legitimate Apple `error` enum cases at URL leafs == "error")

    @Test(
        "`Error` title at a URL whose leaf is NOT `error` trips the gate (poison)",
        arguments: [
            URL(string: "https://developer.apple.com/documentation/pdfkit/pdfviewdelegate/pdfviewparentviewcontroller()")!,
            URL(string: "https://developer.apple.com/documentation/swiftui/view")!,
            URL(string: "https://developer.apple.com/documentation/swiftui/navigationstack")!,
        ]
    )
    func errorTitleAtUnrelatedURLIsPoison(url: URL) {
        #expect(SUT.titleLooksLikePlaceholderError("Error", url: url) == true)
        #expect(SUT.titleLooksLikePlaceholderError("error", url: url) == true)
        #expect(SUT.titleLooksLikePlaceholderError("  ERROR  ", url: url) == true)
    }

    @Test(
        "`Error` title at a URL whose leaf IS `error` is a legitimate Apple enum case — must NOT trip the gate",
        arguments: [
            // The corpus dry-run found these false-positives in the
            // pre-fix gate; they are real Apple symbols, not poison.
            URL(string: "https://developer.apple.com/documentation/storekit/producticonphase/error")!,
            URL(string: "https://developer.apple.com/documentation/storekit/skpaymenttransaction/error")!,
            URL(string: "https://developer.apple.com/documentation/storekit/skdownload/error")!,
            URL(string: "https://developer.apple.com/documentation/storekit/skerror/error")!,
            // Case-variants (Apple sometimes lower-cases the framework segment).
            URL(string: "https://developer.apple.com/documentation/StoreKit/ProductIconPhase/error")!,
        ]
    )
    func errorTitleAtErrorLeafIsLegitimate(url: URL) {
        #expect(SUT.titleLooksLikePlaceholderError("Error", url: url) == false)
        #expect(SUT.titleLooksLikePlaceholderError("error", url: url) == false)
    }

    @Test("`Error` title without URL context defaults to PASS (conservative — don't drop legitimate symbols)")
    func errorTitleWithoutURLIsPassThrough() {
        // No URL context = no way to disambiguate enum-case `error` from
        // renderer-poison "Error". Per #588 principle 3 (no content
        // lost at the door), pass through — the door tier-C check
        // surfaces real conflicts downstream.
        #expect(SUT.titleLooksLikePlaceholderError("Error") == false)
        #expect(SUT.titleLooksLikePlaceholderError("error") == false)
    }

    @Test(
        "real Apple doc titles do NOT trip the gate",
        arguments: [
            "View",
            "NavigationStack",
            "init(rawValue:)",
            "Errors", // plural is fine — many real docs cover error types
            "Error Handling", // valid doc topic
            "Handling Errors in Your App",
            "Apple Developer Documentation Strategy", // longer title containing the placeholder string
            "WKWebView",
            "SwiftUI",
            "PDFViewParentViewController()",
        ]
    )
    func realTitlesAreNotFalsePositives(title: String) {
        #expect(SUT.titleLooksLikePlaceholderError(title) == false)
        let anyURL = URL(string: "https://developer.apple.com/documentation/swiftui/view")!
        #expect(SUT.titleLooksLikePlaceholderError(title, url: anyURL) == false)
    }
}
