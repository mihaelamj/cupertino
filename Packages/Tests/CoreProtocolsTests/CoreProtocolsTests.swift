@testable import CoreProtocols
import Foundation
import Resources
import SharedConstants
import SharedModels
import Testing

// MARK: - CoreProtocols Public API Smoke Tests

// CoreProtocols sits at the bottom of the protocols + Core-namespace
// tier. It owns the `Core` and `Core.Protocols` namespace anchors plus
// every protocol the crawl/fetch/transform layers conform to:
// ContentFetcher, ContentTransformer, CrawlerEngine, plus the
// ExclusionList loader, GitHubCanonicalizer actor, and the
// SwiftPackagesCatalog data shape.
//
// Per #386 independence acceptance: CoreProtocols imports only
// Foundation + Resources + SharedConstants + SharedCore + SharedModels.
// No behavioural cross-package import.
// `grep -rln "^import " Packages/Sources/CoreProtocols/` returns
// exactly those five imports.
//
// These tests guard the public surface against accidental renames
// during refactor passes. Conformance tests live alongside concrete
// implementers (Crawler, Core.Parser.HTML, Core.JSONParser, …) where
// the producers can be wired up against fixtures.

@Suite("CoreProtocols public surface")
struct CoreProtocolsPublicSurfaceTests {
    // MARK: Namespace anchors

    @Test("Core and Core.Protocols namespaces reachable")
    func coreAndProtocolsNamespaces() {
        _ = Core.self
        _ = Core.Protocols.self
    }

    // MARK: ContentFetcher

    @Test("Core.Protocols.FetchResult round-trips its inputs")
    func contentFetcherFetchResult() throws {
        // FetchResult is the post-redirect URL carrier added in #277 and
        // consumed by every crawler engine. Pin the field shape so a
        // refactor doesn't drop responseHeaders or break the init.
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui"))
        let result = Core.Protocols.FetchResult(
            content: "hello",
            url: url,
            responseHeaders: ["Content-Type": "text/html"]
        )
        #expect(result.content == "hello")
        #expect(result.url == url)
        #expect(result.responseHeaders?["Content-Type"] == "text/html")
    }

    @Test("Core.Protocols.FetchResult allows nil response headers")
    func contentFetcherFetchResultNilHeaders() throws {
        let url = try #require(URL(string: "https://example.com"))
        let result = Core.Protocols.FetchResult(content: 42, url: url)
        #expect(result.content == 42)
        #expect(result.responseHeaders == nil)
    }

    // MARK: ContentTransformer

    @Test("Core.Protocols.TransformResult exposes markdown/links/metadata/structuredPage")
    func contentTransformerTransformResult() throws {
        let metadata = Core.Protocols.TransformMetadata(
            title: "Title",
            description: "Description",
            framework: "SwiftUI",
            platforms: ["iOS"],
            isDeprecated: false
        )
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/view"))
        let result = Core.Protocols.TransformResult(
            markdown: "# View",
            links: [url],
            metadata: metadata,
            structuredPage: nil
        )
        #expect(result.markdown == "# View")
        #expect(result.links == [url])
        #expect(result.metadata?.title == "Title")
        #expect(result.metadata?.framework == "SwiftUI")
        #expect(result.metadata?.platforms == ["iOS"])
        #expect(result.metadata?.isDeprecated == false)
        #expect(result.structuredPage == nil)
    }

    // MARK: ExclusionList

    @Test("Core.Protocols.ExclusionList.normalise strips whitespace and lowercases")
    func exclusionListNormalise() {
        // The exclusion-list format is a plain text file of one slug per
        // line; entries can carry stray whitespace or differ in case
        // across hand-curated files. Pin the normalisation contract so
        // a consumer comparing against it doesn't go off-rails.
        #expect(Core.Protocols.ExclusionList.normalise("  SwiftUI  ") == "swiftui")
        #expect(Core.Protocols.ExclusionList.normalise("UIKit") == "uikit")
        #expect(Core.Protocols.ExclusionList.normalise("") == "")
    }

    // MARK: GitHubCanonicalizer

    @Test("Core.Protocols.GitHubCanonicalizer.CanonicalName round-trips owner + repo")
    func gitHubCanonicalizerCanonicalName() {
        let name = Core.Protocols.GitHubCanonicalizer.CanonicalName(owner: "apple", repo: "swift")
        #expect(name.owner == "apple")
        #expect(name.repo == "swift")
        // Equatable is part of the contract; conform-by-rename would
        // silently break dedup logic downstream.
        #expect(name == Core.Protocols.GitHubCanonicalizer.CanonicalName(owner: "apple", repo: "swift"))
    }

    @Test("Core.Protocols.GitHubCanonicalizer primes and snapshots its cache")
    func gitHubCanonicalizerCachePrimeAndSnapshot() async {
        // Don't write to disk for a smoke test; the actor accepts any
        // cache URL and only persists on demand.
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-leaf386-\(UUID().uuidString).json")
        let canonicalizer = Core.Protocols.GitHubCanonicalizer(cacheURL: cacheURL)
        await canonicalizer.primeCache(
            inputOwner: "Mihaela",
            inputRepo: "Cupertino",
            canonicalOwner: "mihaelamj",
            canonicalRepo: "cupertino"
        )
        let snapshot = await canonicalizer.cacheSnapshot()
        // The snapshot key shape (input owner+repo lowercased) is an
        // implementation detail of the actor; instead of pinning the
        // exact key, just verify at least one entry now exists.
        #expect(!snapshot.isEmpty)
    }

    // MARK: SwiftPackagesCatalog

    @Test("Core.Protocols.SwiftPackageEntry decodes from canonical JSON")
    func swiftPackageEntryDecodes() throws {
        // Post-#161 the catalog is slimmed to URL-only, but the on-disk
        // entry schema preserves the rich shape (owner / repo / url /
        // description / stars / language / license / fork / archived /
        // updatedAt) so legacy JSON archives still decode. Pin the
        // required-key set so a refactor doesn't drop one.
        let json = """
        {
            "owner": "apple",
            "repo": "swift-collections",
            "url": "https://github.com/apple/swift-collections",
            "stars": 3000,
            "fork": false,
            "archived": false
        }
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(Core.Protocols.SwiftPackageEntry.self, from: json)
        #expect(entry.owner == "apple")
        #expect(entry.repo == "swift-collections")
        #expect(entry.url == "https://github.com/apple/swift-collections")
        #expect(entry.stars == 3000)
        #expect(entry.fork == false)
        #expect(entry.archived == false)
        #expect(entry.description == nil)
    }

    @Test("Core.Protocols.SwiftPackagesCatalog reads from the embedded URL list")
    func swiftPackagesCatalogLoads() async {
        // Post-#161 the catalog is materialised lazily out of
        // Resources.Embedded.SwiftPackagesCatalog.urls. Pin that the
        // loaded count matches the embedded count and the version /
        // source markers are non-empty.
        let count = await Core.Protocols.SwiftPackagesCatalog.count
        let version = await Core.Protocols.SwiftPackagesCatalog.version
        let source = await Core.Protocols.SwiftPackagesCatalog.source
        #expect(count > 0)
        #expect(count == Resources.Embedded.SwiftPackagesCatalog.urls.count)
        #expect(!version.isEmpty)
        #expect(!source.isEmpty)
    }
}
