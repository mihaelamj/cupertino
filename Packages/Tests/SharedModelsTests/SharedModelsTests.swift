import Foundation
import SharedConstants
import Testing

// MARK: - SharedModels Public API Smoke Tests

// SharedModels sits one rung above SharedUtils. It imports Foundation +
// CryptoKit (for SHA-256 over content) + SharedConstants + SharedUtils.
// It owns the canonical data shapes that flow through every other
// cupertino layer: crawl metadata, structured documentation pages,
// package references, hash utilities, URL utilities, cleanup progress.
//
// Per #384 independence acceptance: SharedModels imports only Foundation
// + CryptoKit + SharedConstants + SharedUtils. No behavioural cross-
// package import.
// `grep -rln "^import " Packages/Sources/Shared/Models/` returns exactly
// `CryptoKit`, `Foundation`, `SharedConstants`, `SharedUtils`.
//
// These tests guard the public surface against accidental renames
// during refactor passes; behavioural tests live alongside the producers
// that drive the models (SharedCoreTests covers CrawlMetadata save/load
// round-trips, CrawlerTests cover the structured-page hash derivation).

@Suite("SharedModels public surface")
struct SharedModelsPublicSurfaceTests {
    @Test("Shared.Models namespace reachable")
    func sharedModelsNamespace() {
        _ = Shared.Models.self
    }

    // MARK: HashUtilities

    @Test("HashUtilities SHA-256 over a string is deterministic")
    func hashUtilitiesSHA256String() {
        let a = Shared.Models.HashUtilities.sha256(of: "leaf-384")
        let b = Shared.Models.HashUtilities.sha256(of: "leaf-384")
        #expect(a == b)
        #expect(a.count == 64) // 32 bytes hex-encoded
    }

    @Test("HashUtilities SHA-256 over data is deterministic")
    func hashUtilitiesSHA256Data() {
        let data = Data("leaf-384".utf8)
        let a = Shared.Models.HashUtilities.sha256(of: data)
        let b = Shared.Models.HashUtilities.sha256(of: data)
        #expect(a == b)
        #expect(a.count == 64)
    }

    // MARK: URLUtilities

    @Test("URLUtilities normalize lowercases and strips fragment/query")
    func urlUtilitiesNormalize() throws {
        let url = try #require(URL(string: "https://developer.apple.com/Documentation/SwiftUI/View?foo=1#bar"))
        let normalized = Shared.Models.URLUtilities.normalize(url)
        #expect(normalized?.path == "/documentation/swiftui/view")
        #expect(normalized?.query == nil)
        #expect(normalized?.fragment == nil)
    }

    @Test("URLUtilities normalize collapses underscore at sub-page depth")
    func urlUtilitiesNormalizeSubpageUnderscore() throws {
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/some_method"))
        let normalized = Shared.Models.URLUtilities.normalize(url)
        #expect(normalized?.path == "/documentation/swiftui/some-method")
    }

    @Test("URLUtilities.filename — siblings with same leaf name under different parents produce distinct filenames (#293)")
    func urlUtilitiesFilenameDistinguishesParents() throws {
        // The bug fixed in #293: when two Apple symbols share a leaf
        // name (`init(rawvalue:)`, `init(_:)`, `subscript(_:)`, etc.) but
        // live under different parent types in the same framework, the
        // old indexer path produced identical filenames and clobbered
        // one of them in the search-index. `URLUtilities.filename(from:)`
        // bakes the full URL path + an 8-byte SHA-256 disambiguator
        // suffix when special chars are present, so the two cases below
        // must yield different filenames.
        let a = try #require(URL(string: "https://developer.apple.com/documentation/accelerate/sparsepreconditioner_t/init(rawvalue:)"))
        let b = try #require(URL(string: "https://developer.apple.com/documentation/accelerate/quadrature_integrator/init(rawvalue:)"))
        let fa = Shared.Models.URLUtilities.filename(from: a)
        let fb = Shared.Models.URLUtilities.filename(from: b)
        #expect(fa != fb)
        // And both must NOT collapse to the bare leaf (`init(rawvalue:)`)
        // that the pre-fix indexer site at
        // `Search/Strategies/Search.Strategies.AppleDocs.swift:217` produced.
        #expect(!fa.hasPrefix("init"))
        #expect(!fb.hasPrefix("init"))
    }

    @Test("URLUtilities.filename — three siblings sharing init(_:) all distinct (RealityKit case)")
    func urlUtilitiesFilenameRealityKitInitCollisions() throws {
        // Worst-case from #293: `apple-docs://realitykit/init(_:)` collided
        // across many RealityKit types pre-fix. Three sample sibling URLs
        // must produce three different filenames.
        let urls = try [
            #require(URL(string: "https://developer.apple.com/documentation/realitykit/meshmodelcollection/init(_:)")),
            #require(URL(string: "https://developer.apple.com/documentation/realitykit/meshbuffer/init(_:)-11fcy")),
            #require(URL(string: "https://developer.apple.com/documentation/realitykit/manipulationcomponent/inputdevice/kind-swift.enum/set/init(_:)")),
        ]
        let filenames = urls.map { Shared.Models.URLUtilities.filename(from: $0) }
        let unique = Set(filenames)
        #expect(unique.count == 3, "all 3 sibling URLs must produce distinct filenames (got \(filenames))")
    }

    // MARK: PackageReference

    @Test("PackageReference type is reachable")
    func packageReferenceType() {
        _ = Shared.Models.PackageReference.self
    }

    // MARK: CrawlMetadata + nested types

    @Test("CrawlMetadata, FrameworkStats, PageMetadata, CrawlStatistics, CrawlSessionState all reachable")
    func crawlMetadataFamily() {
        _ = Shared.Models.CrawlMetadata.self
        _ = Shared.Models.FrameworkStats.self
        _ = Shared.Models.PageMetadata.self
        _ = Shared.Models.CrawlStatistics.self
        _ = Shared.Models.CrawlSessionState.self
    }

    @Test("CrawlStatus enum has the expected raw values")
    func crawlStatusRawValues() {
        // The string raw values back the on-disk JSON metadata format.
        // Renaming any of these would silently invalidate older session
        // files. Pin them so a refactor flags it as a test break.
        let allCases: [Shared.Models.FrameworkStats.CrawlStatus] = [
            .notStarted,
            .inProgress,
            .complete,
            .partial,
            .failed,
        ]
        #expect(allCases.map(\.rawValue).sorted() == ["complete", "failed", "in_progress", "not_started", "partial"])
    }

    // MARK: StructuredDocumentationPage

    @Test("StructuredDocumentationPage type is reachable")
    func structuredDocumentationPageType() {
        _ = Shared.Models.StructuredDocumentationPage.self
    }

    // MARK: CleanupProgress

    @Test("CleanupProgress type is reachable")
    func cleanupProgressType() {
        _ = Shared.Models.CleanupProgress.self
    }
}
