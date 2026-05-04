@testable import Core
import Foundation
@testable import Shared
import Testing

// MARK: - canonicalPath(forDocURI:)

@Test("canonicalPath strips doc:// prefix and bundle, lowercases path")
func canonicalPathStripsBundle() {
    let key = RefResolver.canonicalPath(
        forDocURI: "doc://com.apple.storekit/documentation/StoreKit/AnyTransaction"
    )
    #expect(key == "/documentation/storekit/anytransaction")
}

@Test("canonicalPath handles fragment by stripping it")
func canonicalPathStripsFragment() {
    let key = RefResolver.canonicalPath(
        forDocURI: "doc://com.apple.storekit/documentation/StoreKit/billing#Detect-a-Refund"
    )
    #expect(key == "/documentation/storekit/billing")
}

@Test("canonicalPath handles the apple-documentation generic bundle")
func canonicalPathHandlesGenericBundle() {
    let key = RefResolver.canonicalPath(
        forDocURI: "doc://com.apple.documentation/documentation/AppStoreServerNotifications"
    )
    #expect(key == "/documentation/appstoreservernotifications")
}

@Test("canonicalPath returns nil for non-doc URIs")
func canonicalPathRejectsNonDocURI() {
    #expect(RefResolver.canonicalPath(forDocURI: "https://example.com/x") == nil)
    #expect(RefResolver.canonicalPath(forDocURI: "doc://") == nil) // no path
    #expect(RefResolver.canonicalPath(forDocURI: "doc:something") == nil)
}

@Test("canonicalPath(forURL:) lowercases the URL path")
func canonicalPathFromURL() throws {
    let url = try #require(URL(string: "https://developer.apple.com/documentation/StoreKit/AnyTransaction"))
    #expect(RefResolver.canonicalPath(forURL: url) == "/documentation/storekit/anytransaction")
}

// MARK: - rewriteMarkdown — markdown link form

@Test("rewriteMarkdown rewrites a markdown-link doc:// marker, preserving label")
func rewriteMarkdownPreservesLabel() {
    let map = ["/documentation/storekit/anytransaction": "AnyTransaction"]
    let input = "See [a transaction](doc://com.apple.storekit/documentation/StoreKit/AnyTransaction) here."
    let result = RefResolver.rewriteMarkdown(input, with: map)
    #expect(result.rewritten == "See [a transaction] here.")
    #expect(result.resolvedCount == 1)
    #expect(result.unresolvedMarkers.isEmpty)
}

@Test("rewriteMarkdown uses title when label is empty")
func rewriteMarkdownFallsBackToTitle() {
    let map = ["/documentation/storekit/anytransaction": "AnyTransaction"]
    let input = "See [](doc://com.apple.storekit/documentation/StoreKit/AnyTransaction) here."
    let result = RefResolver.rewriteMarkdown(input, with: map)
    #expect(result.rewritten == "See [AnyTransaction] here.")
}

// MARK: - rewriteMarkdown — bare bracket and bare paren forms

@Test("rewriteMarkdown rewrites a bare bracketed doc:// marker")
func rewriteMarkdownBareBracket() {
    let map = ["/documentation/storekit/anytransaction": "AnyTransaction"]
    let input = "Use [doc://com.apple.storekit/documentation/StoreKit/AnyTransaction] for any."
    let result = RefResolver.rewriteMarkdown(input, with: map)
    #expect(result.rewritten == "Use [AnyTransaction] for any.")
    #expect(result.resolvedCount == 1)
}

@Test("rewriteMarkdown rewrites a parenthesised bare doc:// marker")
func rewriteMarkdownBareParen() {
    let map = ["/documentation/storekit/anytransaction": "AnyTransaction"]
    let input = "(doc://com.apple.storekit/documentation/StoreKit/AnyTransaction)"
    let result = RefResolver.rewriteMarkdown(input, with: map)
    #expect(result.rewritten == "(AnyTransaction)")
}

// MARK: - rewriteMarkdown — multiple markers per input

@Test("rewriteMarkdown handles multiple markers across forms in one document")
func rewriteMarkdownMultipleMarkers() {
    let map = [
        "/documentation/storekit/anytransaction": "AnyTransaction",
        "/documentation/storekit/billing": "Billing",
    ]
    let input = """
    See [link a](doc://com.apple.storekit/documentation/StoreKit/AnyTransaction) and \
    [doc://com.apple.storekit/documentation/StoreKit/Billing] for more.
    """
    let result = RefResolver.rewriteMarkdown(input, with: map)
    #expect(result.rewritten.contains("[link a]"))
    #expect(result.rewritten.contains("[Billing]"))
    #expect(result.resolvedCount == 2)
}

// MARK: - rewriteMarkdown — unresolved markers

@Test("rewriteMarkdown leaves unresolved markers intact and reports them")
func rewriteMarkdownTracksUnresolved() {
    let map: [String: String] = [:]
    let unknown = "doc://com.apple.storekit/documentation/StoreKit/Unknown"
    let input = "Look at [doc](\(unknown)) over there."
    let result = RefResolver.rewriteMarkdown(input, with: map)
    #expect(result.rewritten == input)
    #expect(result.resolvedCount == 0)
    #expect(result.unresolvedMarkers == [unknown])
}

@Test("rewriteMarkdown is idempotent on already-resolved input")
func rewriteMarkdownIdempotent() {
    let map = ["/documentation/storekit/anytransaction": "AnyTransaction"]
    let input = "See [AnyTransaction] here."
    let result = RefResolver.rewriteMarkdown(input, with: map)
    #expect(result.rewritten == input)
    #expect(result.resolvedCount == 0)
    #expect(result.unresolvedMarkers.isEmpty)
}

// MARK: - End-to-end harvest+rewrite on a fixture corpus

@Suite("RefResolver end-to-end")
struct RefResolverEndToEnd {
    /// Spin up a temp directory with a small synthetic corpus, run
    /// resolve, then return the temp directory and the rewritten pages.
    static func makeFixture() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("refresolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Page A: lists Page B in its sections (so Page B's title gets harvested
        // from A's items). A's rawMarkdown contains a doc:// marker pointing to B.
        let pageBURL = URL(string: "https://developer.apple.com/documentation/StoreKit/AnyTransaction")!
        let pageA = StructuredDocumentationPage(
            url: URL(string: "https://developer.apple.com/documentation/StoreKit")!,
            title: "StoreKit",
            kind: .framework,
            source: .appleJSON,
            sections: [
                StructuredDocumentationPage.Section(
                    title: "Topics",
                    items: [
                        .init(name: "AnyTransaction", description: nil, url: pageBURL),
                    ]
                ),
            ],
            rawMarkdown: "See [doc://com.apple.storekit/documentation/StoreKit/AnyTransaction] for details. " +
                "Also unknown [doc://com.apple.storekit/documentation/StoreKit/Phantom].",
            crawledAt: Date(),
            contentHash: "hashA"
        )
        let pageB = StructuredDocumentationPage(
            url: pageBURL,
            title: "AnyTransaction",
            kind: .struct,
            source: .appleJSON,
            sections: [],
            rawMarkdown: "Body of B with no markers.",
            crawledAt: Date(),
            contentHash: "hashB"
        )

        try encoder.encode(pageA).write(to: tmp.appendingPathComponent("storekit_a.json"))
        try encoder.encode(pageB).write(to: tmp.appendingPathComponent("storekit_b.json"))

        // metadata.json must be ignored by the resolver
        try Data("{}".utf8).write(to: tmp.appendingPathComponent("metadata.json"))

        return tmp
    }

    @Test("end-to-end: harvests, rewrites markdown-bracket marker, leaves unknown intact")
    func endToEndHarvestAndRewrite() throws {
        let tmp = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolver = RefResolver(inputDirectory: tmp)
        let (stats, unresolved) = try resolver.run()

        #expect(stats.pagesScanned == 2)
        #expect(stats.refsHarvested >= 2)
        #expect(stats.markersFound == 2)
        #expect(stats.markersResolvedFromHarvest == 1)
        #expect(unresolved.count == 1)
        #expect(unresolved.first?.contains("Phantom") == true)
        #expect(stats.pagesRewritten == 1)

        // Read Page A back and verify the rewrite landed.
        let pageAData = try Data(contentsOf: tmp.appendingPathComponent("storekit_a.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pageA = try decoder.decode(StructuredDocumentationPage.self, from: pageAData)
        #expect(pageA.rawMarkdown?.contains("[AnyTransaction]") == true)
        #expect(pageA.rawMarkdown?.contains("Phantom") == true) // still present, unresolved
        #expect(pageA.contentHash == "hashA") // resolve-refs must NOT bump contentHash
    }

    @Test("end-to-end: a second run is a no-op (idempotent)")
    func endToEndIdempotent() throws {
        let tmp = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolver = RefResolver(inputDirectory: tmp)
        let firstRun = try resolver.run()
        let secondRun = try resolver.run()
        // Second run finds the same markers but resolves the same one — so
        // resolvedCount stays equal; only `pagesRewritten` may drop because
        // the file content is now stable.
        #expect(secondRun.stats.pagesRewritten == 0)
        #expect(secondRun.unresolvedMarkers == firstRun.unresolvedMarkers)
    }

    @Test("end-to-end: skips metadata.json")
    func endToEndIgnoresMetadata() throws {
        let tmp = try Self.makeFixture()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolver = RefResolver(inputDirectory: tmp)
        let pages = try resolver.collectPageFiles()
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { $0.lastPathComponent != "metadata.json" })
    }
}

// MARK: - Network fetcher integration

/// Test double for `RefResolver.TitleFetcher`: returns canned titles
/// for specific URL paths, nil for everything else. Records call count.
private final class MockTitleFetcher: RefResolver.TitleFetcher, @unchecked Sendable {
    let map: [String: String]
    private let queue = DispatchQueue(label: "mock-title-fetcher")
    private var _callCount = 0
    var callCount: Int {
        queue.sync { _callCount }
    }

    init(_ map: [String: String]) {
        self.map = map
    }

    func resolveTitle(for documentationURL: URL) async -> String? {
        queue.sync { _callCount += 1 }
        return map[documentationURL.path.lowercased()]
    }
}

@Suite("RefResolver with network fallback")
struct RefResolverNetwork {
    @Test("network fetcher fills in unresolved markers")
    func networkFetcherFillsTheGap() async throws {
        let tmp = try RefResolverEndToEnd.makeFixture()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let phantomPath = "/documentation/storekit/phantom"
        let fetcher = MockTitleFetcher([phantomPath: "Phantom"])
        let resolver = RefResolver(inputDirectory: tmp)

        let (stats, unresolved) = try await resolver.runWithFetcher(fetcher)

        #expect(unresolved.isEmpty, "fetcher should resolve every previously-unresolved marker")
        #expect(stats.markersResolvedFromNetwork == 1)
        #expect(fetcher.callCount == 1)

        // Verify rewrite landed for the phantom marker
        let pageA = try Self.loadPageA(in: tmp)
        #expect(pageA.rawMarkdown?.contains("[Phantom]") == true)
        #expect(pageA.rawMarkdown?.contains("Phantom]") == true)
        #expect(pageA.rawMarkdown?.contains("[doc://com.apple.storekit/documentation/StoreKit/Phantom]") == false)
    }

    @Test("network fetcher returning nil leaves marker unresolved")
    func networkFetcherNilFallthrough() async throws {
        let tmp = try RefResolverEndToEnd.makeFixture()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fetcher = MockTitleFetcher([:]) // never finds anything
        let resolver = RefResolver(inputDirectory: tmp)

        let (stats, unresolved) = try await resolver.runWithFetcher(fetcher)

        #expect(unresolved.count == 1, "unresolved marker should remain")
        #expect(stats.markersResolvedFromNetwork == 0)
        #expect(fetcher.callCount == 1)
    }

    @Test("CompositeTitleFetcher tries fallback when primary returns nil")
    func compositeChainsFallback() async throws {
        let primary = MockTitleFetcher([:])
        let fallback = MockTitleFetcher(["/documentation/x/y": "Y"])
        let composite = CompositeTitleFetcher(primary: primary, fallback: fallback)
        let url = try #require(URL(string: "https://developer.apple.com/documentation/X/Y"))

        let title = await composite.resolveTitle(for: url)
        #expect(title == "Y")
        #expect(primary.callCount == 1)
        #expect(fallback.callCount == 1)
    }

    @Test("CompositeTitleFetcher does not call fallback when primary succeeds")
    func compositeShortCircuits() async throws {
        let primary = MockTitleFetcher(["/documentation/x/y": "Y"])
        let fallback = MockTitleFetcher([:])
        let composite = CompositeTitleFetcher(primary: primary, fallback: fallback)
        let url = try #require(URL(string: "https://developer.apple.com/documentation/X/Y"))

        let title = await composite.resolveTitle(for: url)
        #expect(title == "Y")
        #expect(primary.callCount == 1)
        #expect(fallback.callCount == 0)
    }

    @Test("documentationURL(forDocURI:) builds the canonical https URL")
    func documentationURLBuilder() {
        let url = RefResolver.documentationURL(
            forDocURI: "doc://com.apple.storekit/documentation/StoreKit/AnyTransaction"
        )
        #expect(url?.absoluteString == "https://developer.apple.com/documentation/storekit/anytransaction")
    }

    private static func loadPageA(in tmp: URL) throws -> StructuredDocumentationPage {
        let data = try Data(contentsOf: tmp.appendingPathComponent("storekit_a.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StructuredDocumentationPage.self, from: data)
    }
}
