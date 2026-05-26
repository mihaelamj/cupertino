import Foundation
@testable import Services
import ServicesModels
import Testing

// MARK: - Services.ReadService URI scheme routing (#1039)

//
// Pins the post-#1037 per-source URI dispatch in `ReadService.read`.
// Pre-fix every docs URI routed to a single `searchDB` URL (the
// legacy monolithic search.db); post-fix `read` accepts an optional
// `docsDBURLs: [String: URL]` map keyed by source-id and picks the
// right per-source DB file based on the URI's scheme. The mapping
// preserves back-compat (nil map or unknown scheme falls back to
// `searchDB`) so existing callers + tests that pin the old shape
// keep working.

@Suite("Services.ReadService URI scheme routing (#1039)")
struct ServicesReadServiceURIRoutingTests {
    private let fallback = URL(fileURLWithPath: "/tmp/legacy/search.db")
    private let appleDocsDB = URL(fileURLWithPath: "/tmp/per-source/apple-documentation.db")
    private let higDB = URL(fileURLWithPath: "/tmp/per-source/hig.db")
    private let swiftEvoDB = URL(fileURLWithPath: "/tmp/per-source/swift-evolution.db")

    private var productionishMap: [String: URL] {
        [
            "apple-docs": appleDocsDB,
            "hig": higDB,
            "swift-evolution": swiftEvoDB,
        ]
    }

    // MARK: - Happy path: URI scheme matches a map key

    @Test("apple-docs URI routes to apple-documentation.db")
    func appleDocsURIRoutesToOwnDB() {
        let url = Services.ReadService.resolveDocsDBURL(
            identifier: "apple-docs://swiftui/view",
            fallback: fallback,
            docsDBURLs: productionishMap
        )
        #expect(url.path == appleDocsDB.path)
    }

    @Test("hig URI routes to hig.db (post-#1037 the previously-broken case)")
    func higURIRoutesToHigDB() {
        let url = Services.ReadService.resolveDocsDBURL(
            identifier: "hig://buttons/standard-button",
            fallback: fallback,
            docsDBURLs: productionishMap
        )
        #expect(url.path == higDB.path)
    }

    @Test("swift-evolution URI routes to swift-evolution.db")
    func swiftEvolutionURIRoutesToOwnDB() {
        let url = Services.ReadService.resolveDocsDBURL(
            identifier: "swift-evolution://proposals/SE-0001",
            fallback: fallback,
            docsDBURLs: productionishMap
        )
        #expect(url.path == swiftEvoDB.path)
    }

    // MARK: - Fallback paths

    @Test("Nil map falls back to the legacy searchDB URL (pre-#1037 callers + tests)")
    func nilMapFallsBackToLegacy() {
        let url = Services.ReadService.resolveDocsDBURL(
            identifier: "apple-docs://swiftui/view",
            fallback: fallback,
            docsDBURLs: nil
        )
        #expect(url.path == fallback.path)
    }

    @Test("Empty map falls back to the legacy searchDB URL")
    func emptyMapFallsBackToLegacy() {
        let url = Services.ReadService.resolveDocsDBURL(
            identifier: "apple-docs://swiftui/view",
            fallback: fallback,
            docsDBURLs: [:]
        )
        #expect(url.path == fallback.path)
    }

    @Test("URI with a scheme not in the map falls back to the legacy searchDB URL")
    func unknownSchemeFallsBackToLegacy() {
        let url = Services.ReadService.resolveDocsDBURL(
            identifier: "future-source://something/foo",
            fallback: fallback,
            docsDBURLs: productionishMap
        )
        #expect(url.path == fallback.path)
    }

    @Test("Identifier without a scheme separator falls back to the legacy searchDB URL")
    func schemelessIdentifierFallsBackToLegacy() {
        // Non-URI identifiers (sample-id, owner/repo paths) are
        // routed through the samples / packages backends, not docs.
        // ReadService still computes the resolved docs URL up front,
        // so this helper must return SOMETHING; the legacy fallback
        // is the safe default.
        let url = Services.ReadService.resolveDocsDBURL(
            identifier: "swiftui-landmarks-sample",
            fallback: fallback,
            docsDBURLs: productionishMap
        )
        #expect(url.path == fallback.path)
    }

    @Test("Owner/repo identifier (no URI scheme) falls back to the legacy searchDB URL")
    func ownerRepoIdentifierFallsBackToLegacy() {
        let url = Services.ReadService.resolveDocsDBURL(
            identifier: "pointfreeco/swift-snapshot-testing/Sources/SnapshotTesting/Recording.swift",
            fallback: fallback,
            docsDBURLs: productionishMap
        )
        #expect(url.path == fallback.path)
    }
}
