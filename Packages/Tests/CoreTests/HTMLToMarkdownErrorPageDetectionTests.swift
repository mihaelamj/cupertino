@testable import Core
import Foundation
import Testing
import CoreProtocols
@testable import CoreHTMLParser

// Coverage for the `HTMLToMarkdown.looksLikeHTTPErrorPage(...)` helper
// added in #284. The helper gates the crawler's WebView fallback path
// from persisting Apple's CDN-served error templates as if they were
// documentation pages. The shipped v1.0.2 search.db carries 68 such
// poison rows (23 × 403 + 45 × 502) that this helper would have caught
// at crawl time.

@Suite("HTMLToMarkdown.looksLikeHTTPErrorPage (#284)")
struct HTMLToMarkdownErrorPageDetectionTests {
    // MARK: HTTP-status-prefix titles

    @Test("'403 Forbidden' title trips the gate")
    func detectsForbidden() {
        let html = "<html><head><title>403 Forbidden</title></head><body><p>Forbidden.</p></body></html>"
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: html) == true)
    }

    @Test("'502 Bad Gateway' title trips the gate")
    func detectsBadGateway() {
        let html = "<html><head><title>502 Bad Gateway</title></head><body><p>Server error.</p></body></html>"
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: html) == true)
    }

    @Test(
        "All status-prefix codes from the issue spec trip the gate",
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
    func detectsAllStatusPrefixes(title: String) {
        let html = "<html><head><title>\(title)</title></head><body><p>err</p></body></html>"
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: html) == true)
    }

    // MARK: Real Apple titles that LOOK error-adjacent must NOT trip

    @Test("Real Apple symbol page named '...Forbidden...' is not flagged")
    func realForbiddenSymbolNotFlagged() {
        // From the v1.0.2 audit: there are legitimate Apple symbol pages
        // like UIDropOperation.forbidden, MTRAccessControlAccessRestriction-
        // Type.attributeAccessForbidden, etc. None match the status-prefix
        // regex AND they all carry a real documentation body, so word-count
        // pushes them above the 10-word threshold.
        let html = """
        <html><head><title>UIDropOperation.forbidden | Apple Developer Documentation</title></head>
        <body>
        <h1>UIDropOperation.forbidden</h1>
        <p>The drag operation is not permitted at the destination, so a stop
        glyph is rendered next to the cursor while the drag is over the view.
        Use this case when the receiver cannot accept the dragged content but
        wants to communicate that constraint visually.</p>
        </body></html>
        """
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: html) == false)
    }

    @Test("Real Apple symbol page named 'Routing404Type' is not flagged")
    func numericInTitleNotFlagged() {
        let html = """
        <html><head><title>Routing404Type | Apple Developer Documentation</title></head>
        <body><h1>Routing404Type</h1>
        <p>A type that represents the specific kind of 404 routing error
        observed in the request. Used by the routing layer to differentiate
        legitimate not-found cases from misconfigured routes.</p></body></html>
        """
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: html) == false)
    }

    // MARK: word-count defense-in-depth

    @Test("Short body + 'Service Unavailable' phrase trips the defense-in-depth gate")
    func shortBodyServiceUnavailableTrips() {
        let html = "<html><head><title>Service Unavailable</title></head><body><p>Try again later.</p></body></html>"
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: html) == true)
    }

    @Test("Long body containing 'Bad Gateway' phrase in title is NOT flagged once it has real content")
    func longBodyOverridesPhraseHeuristic() {
        // If Apple ever ships a real doc page with one of the error phrases
        // in the title, the word-count threshold should keep us from
        // incorrectly skipping it.
        let body = String(repeating: "word ", count: 50) // 50 whitespace-separated tokens
        let html = "<html><head><title>Handling Bad Gateway Responses</title></head><body><p>\(body)</p></body></html>"
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: html) == false)
    }

    // MARK: degenerate inputs

    @Test("Title-less HTML returns false (the existing nil-title gate handles it)")
    func noTitleReturnsFalse() {
        let html = "<html><body><p>Just a body, no head, no title.</p></body></html>"
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: html) == false)
    }

    @Test("Empty HTML returns false")
    func emptyHTMLReturnsFalse() {
        #expect(HTMLToMarkdown.looksLikeHTTPErrorPage(html: "") == false)
    }
}
