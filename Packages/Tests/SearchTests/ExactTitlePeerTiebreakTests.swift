import SearchModels
import Foundation
@testable import Search
import Testing

// Exact-title peer tiebreak inside HEURISTIC 1 (#256).
//
// When `Result` matches three apple-docs pages with title "Result" — Swift's
// canonical enum, Vision's `VisionRequest.Result` associated type, and
// Installer JS's runtime type — the 50x/20x exact-title boost flattens them
// and BM25F decides among them. BM25F has no opinion about which framework
// is canonical for the bare type name. Two orthogonal tiebreaks separate
// canonical from peer:
//
//   1. URI simplicity — `documentation_FRAMEWORK_QUERY` exactly is the
//      framework's top-level type page; deeper paths are sub-symbols whose
//      title happens to shadow a top-level type elsewhere.
//
//   2. Framework authority — `Search.Index.frameworkAuthority` boosts
//      `swift` / `swiftui` / `foundation`, demotes `installer_js` /
//      `webkitjs` / `javascriptcore` / `devicemanagement`.
//
// These tests exercise the public `search` surface so the boost composition
// is what we actually run, not a synthetic BM25 expression.

private func tempDB() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("exact-title-tiebreak-\(UUID().uuidString).db")
}

private func indexPage(
    on idx: Search.Index,
    uri: String,
    framework: String,
    title: String,
    content: String
) async throws {
    try await idx.indexDocument(
        uri: uri,
        source: "apple-docs",
        framework: framework,
        title: title,
        content: content,
        filePath: "/tmp/\(framework)",
        contentHash: framework,
        lastCrawled: Date()
    )
}

@Suite("Exact title peer tiebreak (#256)")
struct ExactTitlePeerTiebreakTests {
    /// Canonical Swift `Result` enum should outrank a sub-symbol named
    /// "Result" on a different framework's parent type. Sub-symbol is
    /// detected by URI shape: `documentation_vision_visionrequest_result`
    /// is `VisionRequest.Result`, not Vision's top-level Result.
    @Test("Swift Result enum beats Vision.VisionRequest.Result associated type")
    func swiftResultBeatsVisionAssociatedType() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_result",
            framework: "swift",
            title: "Result",
            content: "A value that represents either a success or a failure, including an associated value in each case. Generic over Success and Failure."
        )

        try await indexPage(
            on: idx,
            uri: "apple-docs://vision/documentation_vision_visionrequest_result",
            framework: "vision",
            title: "Result",
            content: "An associated type that represents the result of a VisionRequest."
        )

        let hits = try await idx.search(query: "Result", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_result")
    }

    /// Both Swift and Installer JS have a top-level page named "Result"
    /// (Installer JS is at `documentation_installer_js_result`, where
    /// `installer_js` is the framework slug). URI-simplicity is a tie;
    /// framework authority breaks it: `swift` has multiplier 0.5,
    /// `installer_js` has 1.4.
    @Test("Swift Result beats Installer JS Result via framework authority")
    func swiftResultBeatsInstallerJSTopLevelResult() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_result",
            framework: "swift",
            title: "Result",
            content: "A value that represents either a success or a failure, including an associated value in each case."
        )

        try await indexPage(
            on: idx,
            uri: "apple-docs://installer_js/documentation_installer_js_result",
            framework: "installer_js",
            title: "Result",
            content: "The result of an installer JavaScript operation."
        )

        let hits = try await idx.search(query: "Result", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_result")
    }

    /// The full #256 repro: all three peers indexed together. Swift's
    /// canonical enum must land at #1; the relative order of the other
    /// two is not asserted (out of scope for the issue).
    @Test("Swift Result wins against both Vision sub-symbol and Installer JS top-level")
    func swiftResultWinsAgainstBothPeers() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_result",
            framework: "swift",
            title: "Result",
            content: "A value that represents either a success or a failure, including an associated value in each case."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://vision/documentation_vision_visionrequest_result",
            framework: "vision",
            title: "Result",
            content: "An associated type that represents the result of a VisionRequest."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://installer_js/documentation_installer_js_result",
            framework: "installer_js",
            title: "Result",
            content: "The result of an installer JavaScript operation."
        )

        let hits = try await idx.search(query: "Result", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_result")
    }

    /// Negative coverage: when the user asks for `VisionRequest`, the
    /// authority map must not float a non-existent Swift entry. Vision's
    /// own top-level page must still win.
    @Test("Authority does not crowd out framework-specific exact titles")
    func authorityDoesNotOverrideFrameworkSpecificQueries() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let idx = try await Search.Index(dbPath: dbPath)

        try await indexPage(
            on: idx,
            uri: "apple-docs://vision/documentation_vision_visionrequest",
            framework: "vision",
            title: "VisionRequest",
            content: "A request that the Vision framework executes against an image or video frame."
        )

        // Decoy: a sub-symbol whose title also matches.
        try await indexPage(
            on: idx,
            uri: "apple-docs://vision/documentation_vision_imagerequesthandler_visionrequest",
            framework: "vision",
            title: "VisionRequest",
            content: "A request handler property of type VisionRequest."
        )

        let hits = try await idx.search(query: "VisionRequest", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://vision/documentation_vision_visionrequest")
    }
}
