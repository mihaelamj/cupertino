import CrawlerModels
import Foundation
import SharedConstants
import Testing

// MARK: - Namespace Anchors

@Suite("Crawler namespace anchors")
struct CrawlerNamespaceTests {
    @Test("Crawler namespace is accessible and empty (anchor only)")
    func crawlerNamespaceExists() {
        // The Crawler enum is the cross-target anchor. CrawlerModels owns
        // it so the protocols below can extend Crawler.* without dragging
        // the concrete Crawler target along.
        let _: Crawler.Type = Crawler.self
    }

    @Test("Crawler.WebKit sub-namespace is accessible (anchor only)")
    func webKitNamespaceExists() {
        // Sub-namespace anchor for WKWebView-based fetchers. Concrete
        // actors live in the Crawler target; this is just the empty
        // enum so types in the Crawler target can extend Crawler.WebKit.*.
        let _: Crawler.WebKit.Type = Crawler.WebKit.self
    }
}

// MARK: - PriorityPackageOutcome

@Suite("Crawler.PriorityPackageOutcome value type")
struct PriorityPackageOutcomeTests {
    @Test("Initializes with totalUniqueReposFound")
    func initializesWithCount() {
        let outcome = Crawler.PriorityPackageOutcome(totalUniqueReposFound: 42)
        #expect(outcome.totalUniqueReposFound == 42)
    }

    @Test("Accepts zero count")
    func acceptsZero() {
        let outcome = Crawler.PriorityPackageOutcome(totalUniqueReposFound: 0)
        #expect(outcome.totalUniqueReposFound == 0)
    }

    @Test("Accepts large counts")
    func acceptsLargeCount() {
        let outcome = Crawler.PriorityPackageOutcome(totalUniqueReposFound: 100_000)
        #expect(outcome.totalUniqueReposFound == 100_000)
    }
}

// MARK: - NoopHTMLParserStrategy

@Suite("Crawler.NoopHTMLParserStrategy returns empty defaults")
struct NoopHTMLParserStrategyTests {
    @Test("convert returns empty string for any input")
    func convertReturnsEmpty() {
        let strategy = Crawler.NoopHTMLParserStrategy()
        let url = URL(string: "https://developer.apple.com/documentation/swiftui")!
        #expect(strategy.convert(html: "", url: url) == "")
        #expect(strategy.convert(html: "<html><body>hi</body></html>", url: url) == "")
        #expect(strategy.convert(html: "anything", url: url) == "")
    }

    @Test("toStructuredPage returns nil regardless of inputs")
    func toStructuredPageReturnsNil() {
        let strategy = Crawler.NoopHTMLParserStrategy()
        let url = URL(string: "https://developer.apple.com/documentation/swiftui")!
        #expect(strategy.toStructuredPage(html: "", url: url, source: .appleJSON, depth: nil) == nil)
        #expect(strategy.toStructuredPage(html: "<h1>title</h1>", url: url, source: .appleJSON, depth: 3) == nil)
    }

    @Test("looksLikeHTTPErrorPage always returns false")
    func looksLikeHTTPErrorPageAlwaysFalse() {
        let strategy = Crawler.NoopHTMLParserStrategy()
        #expect(strategy.looksLikeHTTPErrorPage(html: "") == false)
        #expect(strategy.looksLikeHTTPErrorPage(html: "<title>403 Forbidden</title>") == false)
    }

    @Test("looksLikeJavaScriptFallback always returns false")
    func looksLikeJavaScriptFallbackAlwaysFalse() {
        let strategy = Crawler.NoopHTMLParserStrategy()
        #expect(strategy.looksLikeJavaScriptFallback(html: "") == false)
        #expect(strategy.looksLikeJavaScriptFallback(html: "<noscript>requires JS</noscript>") == false)
    }

    @Test("Conforms to HTMLParserStrategy protocol")
    func conformsToProtocol() {
        let strategy: any Crawler.HTMLParserStrategy = Crawler.NoopHTMLParserStrategy()
        // The compile-time conformance is what matters; this runtime
        // check just lets the test framework count it as exercised.
        #expect(type(of: strategy) == Crawler.NoopHTMLParserStrategy.self)
    }
}

// MARK: - NoopAppleJSONParserStrategy

@Suite("Crawler.NoopAppleJSONParserStrategy returns empty defaults")
struct NoopAppleJSONParserStrategyTests {
    @Test("convert returns nil for any JSON")
    func convertReturnsNil() {
        let strategy = Crawler.NoopAppleJSONParserStrategy()
        let url = URL(string: "https://developer.apple.com/tutorials/data/documentation/swiftui.json")!
        #expect(strategy.convert(json: Data(), url: url) == nil)
        #expect(strategy.convert(json: Data("{}".utf8), url: url) == nil)
        #expect(strategy.convert(json: Data("{\"k\":1}".utf8), url: url) == nil)
    }

    @Test("toStructuredPage returns nil for any JSON")
    func toStructuredPageReturnsNil() {
        let strategy = Crawler.NoopAppleJSONParserStrategy()
        let url = URL(string: "https://developer.apple.com/tutorials/data/documentation/swiftui.json")!
        #expect(strategy.toStructuredPage(json: Data(), url: url, depth: nil) == nil)
        #expect(strategy.toStructuredPage(json: Data("{}".utf8), url: url, depth: 2) == nil)
    }

    @Test("jsonAPIURL returns nil for any input URL")
    func jsonAPIURLReturnsNil() {
        let strategy = Crawler.NoopAppleJSONParserStrategy()
        let docURL = URL(string: "https://developer.apple.com/documentation/swiftui/list")!
        #expect(strategy.jsonAPIURL(from: docURL) == nil)
    }

    @Test("documentationURL returns nil for any input URL")
    func documentationURLReturnsNil() {
        let strategy = Crawler.NoopAppleJSONParserStrategy()
        let jsonURL = URL(string: "https://developer.apple.com/tutorials/data/documentation/swiftui/list.json")!
        #expect(strategy.documentationURL(from: jsonURL) == nil)
    }

    @Test("extractLinks returns empty array for any JSON")
    func extractLinksReturnsEmpty() {
        let strategy = Crawler.NoopAppleJSONParserStrategy()
        #expect(strategy.extractLinks(from: Data()).isEmpty)
        #expect(strategy.extractLinks(from: Data("{\"k\":1}".utf8)).isEmpty)
    }

    @Test("Conforms to AppleJSONParserStrategy protocol")
    func conformsToProtocol() {
        let strategy: any Crawler.AppleJSONParserStrategy = Crawler.NoopAppleJSONParserStrategy()
        #expect(type(of: strategy) == Crawler.NoopAppleJSONParserStrategy.self)
    }
}

// MARK: - NoopPriorityPackageStrategy

@Suite("Crawler.NoopPriorityPackageStrategy returns empty outcome")
struct NoopPriorityPackageStrategyTests {
    @Test("generate returns an outcome with zero repos")
    func generateReturnsZero() async throws {
        let strategy = Crawler.NoopPriorityPackageStrategy()
        let swiftOrg = URL(fileURLWithPath: "/tmp/does-not-matter-noop-input")
        let output = URL(fileURLWithPath: "/tmp/does-not-matter-noop-output")
        let outcome = try await strategy.generate(swiftOrgDocsPath: swiftOrg, outputPath: output)
        #expect(outcome.totalUniqueReposFound == 0)
    }

    @Test("generate ignores its URL arguments — never writes anything")
    func generateIsInert() async throws {
        // Two calls with wildly different URLs produce the same outcome.
        // Proves the Noop doesn't touch disk and is safe in any test
        // composition root.
        let strategy = Crawler.NoopPriorityPackageStrategy()
        let outA = try await strategy.generate(
            swiftOrgDocsPath: URL(fileURLWithPath: "/a"),
            outputPath: URL(fileURLWithPath: "/b")
        )
        let outB = try await strategy.generate(
            swiftOrgDocsPath: URL(fileURLWithPath: "/c/d/e"),
            outputPath: URL(fileURLWithPath: "/f")
        )
        #expect(outA.totalUniqueReposFound == outB.totalUniqueReposFound)
        #expect(outA.totalUniqueReposFound == 0)
    }

    @Test("Conforms to PriorityPackageStrategy protocol")
    func conformsToProtocol() {
        let strategy: any Crawler.PriorityPackageStrategy = Crawler.NoopPriorityPackageStrategy()
        #expect(type(of: strategy) == Crawler.NoopPriorityPackageStrategy.self)
    }
}

// MARK: - Cross-strategy invariants

@Suite("Cross-strategy invariants")
struct CrawlerStrategyInvariantsTests {
    @Test("All three Noop strategies are independently instantiable")
    func allThreeNoopsConstruct() {
        // No shared state, no singletons — three Noops can co-exist.
        // This is what lets a test bundle wire all three at once when
        // constructing a Crawler.AppleDocs purely for state-machine
        // coverage.
        let html = Crawler.NoopHTMLParserStrategy()
        let json = Crawler.NoopAppleJSONParserStrategy()
        let priority = Crawler.NoopPriorityPackageStrategy()
        let _: any Crawler.HTMLParserStrategy = html
        let _: any Crawler.AppleJSONParserStrategy = json
        let _: any Crawler.PriorityPackageStrategy = priority
    }
}
