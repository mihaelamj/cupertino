import CoreProtocols
@testable import CoreJSONParser
import Foundation
import Testing

// MARK: - CoreJSONParser Public API Smoke Tests

// CoreJSONParser owns the Apple-docs JSON pipeline: ContentFetcher
// (HTTP), AppleJSONToMarkdown (DocC JSON -> Markdown + links + the
// structured page model), MarkdownToStructuredPage (Markdown ->
// StructuredDocumentationPage), RefResolver (post-pass doc:// -> URL/
// title resolution), and the top-level Engine that wires it all
// together for the Crawler target.
//
// Per #392 independence acceptance: CoreJSONParser imports only
// Foundation + CoreProtocols + SharedCore + SharedModels +
// SharedConstants + SharedUtils + Logging. No behavioural cross-package
// imports beyond that. `grep -rln "^import " Packages/Sources/Core/JSONParser/`
// returns exactly those seven imports.
//
// This is the first test target the package has carried; previous DI
// leaves found existing test targets in place. The behavioural tests
// for the full DocC -> Markdown pipeline live downstream (CoreTests,
// SearchTests) where end-to-end fixtures + indexers can be wired up.
// This suite pins the public surface so the leaf compiles in isolation
// and the API contract holds.

@Suite("CoreJSONParser public surface")
struct CoreJSONParserPublicSurfaceTests {
    // MARK: Namespace

    @Test("Core.JSONParser namespace + version reachable")
    func namespaceAndVersion() {
        _ = Core.JSONParser.self
        // Version is a stable string constant; pinning it ensures an
        // accidental bump lands deliberately. Downstream consumers
        // don't read it today, but it's part of the public surface.
        #expect(Core.JSONParser.version == "1.0.0")
    }

    // MARK: AppleJSONToMarkdown — URL canonicalization helpers

    @Test("jsonAPIURL converts a documentation URL to the JSON-API form")
    func jsonAPIURLForwardConversion() throws {
        let doc = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/view"))
        let api = try #require(Core.JSONParser.AppleJSONToMarkdown.jsonAPIURL(from: doc))
        // Apple's DocC JSON endpoint mirrors the doc URL path under
        // /tutorials/data/ with a .json suffix.
        #expect(api.host == "developer.apple.com")
        #expect(api.path.hasPrefix("/tutorials/data/documentation"))
        #expect(api.path.hasSuffix(".json"))
        #expect(api.absoluteString.lowercased().contains("swiftui"))
    }

    @Test("jsonAPIURL returns nil for non-Apple hosts")
    func jsonAPIURLRejectsNonAppleHost() throws {
        let other = try #require(URL(string: "https://example.com/documentation/swiftui/view"))
        #expect(Core.JSONParser.AppleJSONToMarkdown.jsonAPIURL(from: other) == nil)
    }

    @Test("documentationURL is the inverse of jsonAPIURL for valid Apple-docs URLs")
    func documentationURLRoundTripsAgainstJSONAPIURL() throws {
        // Round-trip is the contract #277 leans on for canonical
        // storage; if the inverse breaks, post-redirect URL plumbing
        // silently loses information.
        let original = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/view"))
        let api = try #require(Core.JSONParser.AppleJSONToMarkdown.jsonAPIURL(from: original))
        let recovered = try #require(Core.JSONParser.AppleJSONToMarkdown.documentationURL(from: api))
        // Case may differ across the round-trip (lowercase canonical
        // form). Compare lowercased paths to express the semantic.
        #expect(recovered.host == "developer.apple.com")
        #expect(recovered.path.lowercased() == original.path.lowercased())
    }

    @Test("documentationURL returns nil for non-Apple hosts")
    func documentationURLRejectsNonAppleHost() throws {
        let other = try #require(URL(string: "https://example.com/tutorials/data/documentation/swiftui.json"))
        #expect(Core.JSONParser.AppleJSONToMarkdown.documentationURL(from: other) == nil)
    }

    // MARK: AppleJSONToMarkdown — value-type construction + protocol conformance

    @Test("AppleJSONToMarkdown init constructs, conforms to ContentTransformer")
    func appleJSONToMarkdownInit() {
        let transformer = Core.JSONParser.AppleJSONToMarkdown()
        // Compile-time existential cast pins the protocol conformance;
        // dropping it would break the engine wiring + every Crawler
        // engine that consumes the transformer.
        let asTransformer: any Core.Protocols.ContentTransformer = transformer
        _ = asTransformer
    }

    @Test("AppleJSONToMarkdown.transform returns nil for malformed JSON")
    func appleJSONToMarkdownTransformMalformed() throws {
        let transformer = Core.JSONParser.AppleJSONToMarkdown()
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/view"))
        let result = transformer.transform(Data("not a json".utf8), url: url)
        // Per docstring contract: invalid JSON returns nil rather
        // than throwing; consumers downstream are nil-guarded.
        #expect(result == nil)
    }

    @Test("AppleJSONToMarkdown.extractLinks returns empty for malformed JSON")
    func appleJSONToMarkdownExtractLinksMalformed() {
        let transformer = Core.JSONParser.AppleJSONToMarkdown()
        let links = transformer.extractLinks(from: Data("not a json".utf8))
        #expect(links.isEmpty)
    }

    // MARK: Engine.Error / ContentFetcher.Error reachable

    @Test("Core.JSONParser.Engine.Error and ContentFetcher.Error reachable")
    func errorTypesReachable() {
        _ = Core.JSONParser.Engine.Error.self
        _ = Core.JSONParser.ContentFetcher.Error.self
    }

    // MARK: ContentFetcher construction + protocol conformance

    @Test("ContentFetcher constructs and conforms to Core.Protocols.ContentFetcher")
    func contentFetcherConformance() {
        let fetcher = Core.JSONParser.ContentFetcher()
        let asFetcher: any Core.Protocols.ContentFetcher = fetcher
        _ = asFetcher
    }

    // MARK: MarkdownToStructuredPage + RefResolver namespaces reachable

    @Test("MarkdownToStructuredPage namespace reachable")
    func markdownToStructuredPageNamespace() {
        _ = Core.JSONParser.MarkdownToStructuredPage.self
    }

    @Test("RefResolver type + Stats struct reachable")
    func refResolverNamespace() {
        _ = Core.JSONParser.RefResolver.self
        _ = Core.JSONParser.RefResolver.Stats.self
    }
}
