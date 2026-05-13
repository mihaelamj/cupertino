@testable import Core
import Foundation
import Testing

// Coverage for `HTMLToMarkdown.looksLikeJavaScriptFallback(...)` — the
// crawler-side gate added on top of #284 to catch Apple's React SPA
// "no-content" sub-views. Apple's developer-docs site is a client-rendered
// React app; when its internal doc-loader endpoint returns 404 (or some
// other failure) for a given URL, the page itself returns HTTP 200 OK
// with the shell HTML and one of two sub-view templates as the body.
//
// Neither sub-view is an HTTP error, so `looksLikeHTTPErrorPage` lets
// them through. The indexer-side `pageLooksLikeJavaScriptFallback`
// (#284, in SearchIndexBuilder) catches the same shape post-conversion,
// but only on the apple-docs index path AND only after the poison file
// has already landed in the source corpus. This crawler-side gate stops
// them at write time so neither the corpus nor any downstream code sees
// them.

@Suite("HTMLToMarkdown.looksLikeJavaScriptFallback (#284 crawler-side)")
struct HTMLToMarkdownJavaScriptFallbackTests {
    // MARK: 404 sub-view ("page can't be found")

    @Test("Apple's React 404 sub-view trips the gate")
    func reactNotFoundSubView() {
        // Sample captured from a v1.0.2-era poison file: HTTP 200, JS ran,
        // React app booted, doc-loader returned 404, sub-view rendered.
        let html = """
        <html><head><title>Apple Developer Documentation</title></head>
        <body>
        <h1>Apple Developer Documentation</h1>
        <a href="#app-main">Skip Navigation</a>
        <h1>The page you're looking for can't be found.</h1>
        <input placeholder="Search developer.apple.com">
        </body></html>
        """
        #expect(HTMLToMarkdown.looksLikeJavaScriptFallback(html: html) == true)
    }

    @Test("Sub-view phrase embedded in a paragraph still trips")
    func subViewInParagraph() {
        let html = """
        <html><body><p>The page you're looking for can't be found.</p></body></html>
        """
        #expect(HTMLToMarkdown.looksLikeJavaScriptFallback(html: html) == true)
    }

    // MARK: generic error sub-view

    @Test("Apple's React 'unknown error' sub-view trips the gate")
    func reactUnknownErrorSubView() {
        let html = """
        <html><head><title>Apple Developer Documentation</title></head>
        <body>
        <h1>Apple Developer Documentation</h1>
        <a href="#app-main">Skip Navigation</a>
        <h1>An unknown error occurred.</h1>
        </body></html>
        """
        #expect(HTMLToMarkdown.looksLikeJavaScriptFallback(html: html) == true)
    }

    // MARK: real Apple pages must NOT trip

    @Test("Real Apple symbol page is not flagged")
    func realPageNotFlagged() {
        let html = """
        <html><head><title>AVCustomMediaSelectionScheme | Apple Developer Documentation</title></head>
        <body>
        <h1>AVCustomMediaSelectionScheme</h1>
        <p>A media selection scheme provides custom settings for controlling
        media presentation in playback and authoring workflows. Use this type
        when the built-in audio and subtitle selection options don't meet
        your app's needs.</p>
        </body></html>
        """
        #expect(HTMLToMarkdown.looksLikeJavaScriptFallback(html: html) == false)
    }

    @Test("Real page legitimately discussing JavaScript APIs is not flagged")
    func realJavaScriptPageNotFlagged() {
        // The gate must not trip on Apple's WebKit / WKWebView pages that
        // legitimately discuss the word "JavaScript" in normal prose.
        // We pin literal phrases unique to React's no-content sub-views,
        // not the substring "JavaScript", to avoid this class of false
        // positive.
        let html = """
        <html><head><title>WKWebView.evaluateJavaScript | Apple Developer Documentation</title></head>
        <body>
        <h1>evaluateJavaScript(_:completionHandler:)</h1>
        <p>Use this method to execute JavaScript code in the context of the
        currently loaded page. Real Apple documentation routinely mentions
        JavaScript without the SPA's no-content sub-view markers; this
        page must therefore not be flagged.</p>
        </body></html>
        """
        #expect(HTMLToMarkdown.looksLikeJavaScriptFallback(html: html) == false)
    }

    @Test("Real page that mentions a similar phrase mid-prose is not flagged")
    func similarPhraseInProseNotFlagged() {
        // Defensively confirm that nearby English phrasing ("can't find
        // the page", "could not be located") doesn't trip the gate —
        // only the literal Apple sub-view sentence does.
        let html = """
        <html><body>
        <p>If a page can't be located the routing layer should surface
        a NotFoundError, not silently drop the request.</p>
        </body></html>
        """
        #expect(HTMLToMarkdown.looksLikeJavaScriptFallback(html: html) == false)
    }

    // MARK: degenerate inputs

    @Test("Empty HTML returns false")
    func emptyHTMLReturnsFalse() {
        #expect(HTMLToMarkdown.looksLikeJavaScriptFallback(html: "") == false)
    }

    @Test("HTML with only a title returns false")
    func titleOnlyReturnsFalse() {
        let html = "<html><head><title>Apple Developer Documentation</title></head></html>"
        #expect(HTMLToMarkdown.looksLikeJavaScriptFallback(html: html) == false)
    }
}
