import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

/// Regression suite for [#630](https://github.com/mihaelamj/cupertino/issues/630).
///
/// `fetchCanonicalTypePages` is the safety-net that probes
/// `apple-docs://<fw>/<query>` for each of `swift` / `swiftui` /
/// `foundation` and force-prepends every hit at rank `-2000`. Pre-#630
/// it returned EVERY row whose URI matched, regardless of `kind` or
/// `title` shape — so a query like `URL` returned `apple-docs://swift/url`
/// (the `String.IntentInputOptions.KeyboardType.URL` enum case stored
/// under that URI in the v1.1.0 corpus) at the top, ahead of legitimate
/// BM25-ranked candidates.
///
/// Post-#630 the prepend filter:
///
/// 1. Rejects rows whose `kind` is in `propertyMethodKinds`
///    (property, method, function, operator, macro, initializer, plus
///    the instance/type variants). Catches `foundation/url` (property
///    URLRequest.url) and `swiftui/urlsession` (property
///    BackgroundTask.urlSession) before they get prepended.
///
/// 2. Rejects rows whose `title` contains a `.`. Apple's canonical
///    type pages carry bare titles (`Task`, `URLSession`) optionally
///    followed by ` | Apple Developer Documentation`. A title like
///    `String.IntentInputOptions.KeyboardType.URL` is a dotted-breadcrumb
///    member-page title, caught here even when kind=unknown.
///
/// 3. Keeps `kind=unknown` rows with bare titles intact, so the Codable
///    safety-net (kind=unknown in the v1.1.0 bundle but title is
///    `Codable | Apple Developer Documentation`) still surfaces.
@Suite("#630 canonical-prepend kind+title filter", .serialized)
struct Issue630CanonicalPrependKindFilterTests {
    // MARK: - Helpers

    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue630-\(UUID().uuidString).db")
    }

    /// Index a row carrying explicit `kind` in the wrapper JSON — the
    /// inference path would otherwise default to `unknown` and bypass
    /// the property-kind filter entirely.
    // swiftlint:disable:next function_parameter_count
    private static func indexRow(
        on idx: Search.Index,
        uri: String,
        framework: String,
        title: String,
        kind: String,
        content: String
    ) async throws {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let jsonData = """
        {"title":"\(escapedTitle)","url":"https://developer.apple.com/documentation/\(framework)/\(title
            .lowercased())","rawMarkdown":"\(escapedContent)","source":"apple-docs","framework":"\(framework)","kind":"\(kind)"}
        """
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: uri,
            source: "apple-docs",
            framework: framework,
            title: title,
            content: content,
            filePath: "/tmp/\(framework)-\(UUID().uuidString)",
            contentHash: UUID().uuidString,
            lastCrawled: Date(),
            jsonData: jsonData
        ))
    }

    // MARK: - 1. property/method kinds are rejected from prepend

    @Test("kind=property at apple-docs://foundation/<query> is NOT force-prepended")
    func propertyKindNotPrepended() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // foundation/widget carries kind=property (collision-clobbered shape,
        // mirrors v1.1.0's foundation/url being URLRequest.url).
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://foundation/widget",
            framework: "foundation",
            title: "widget",
            kind: "property",
            content: "var widget: Widget { get } — A property called widget."
        )
        // A BM25 peer with a higher-quality title so the prepend, if it
        // fires, wins. (If the filter works the peer survives at top.)
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/widget-overview",
            framework: "swiftui",
            title: "Widget | Apple Developer Documentation",
            kind: "struct",
            content: "Widget overview struct in SwiftUI."
        )

        let hits = try await idx.search(query: "Widget", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        // The property row must not be at rank -2000 — it can still appear
        // via BM25, but not as the force-prepended top entry.
        let topURI = hits.first?.uri
        #expect(
            topURI != "apple-docs://foundation/widget",
            "kind=property at foundation/<query> must not be force-prepended"
        )
    }

    @Test("kind=case is rejected when title is dotted-breadcrumb")
    func dottedTitleNotPrepended() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // swift/url stores `String.IntentInputOptions.KeyboardType.URL`
        // (the KeyboardType.url enum case) — kind=unknown but the title
        // is a dotted breadcrumb. Pre-#630 it ranked first for any
        // `URL` query because the prepend force-promoted it to -2000.
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/widgetcase",
            framework: "swift",
            title: "String.IntentInputOptions.KeyboardType.WidgetCase",
            kind: "unknown",
            content: "An enum case nested deep inside another type."
        )
        // BM25 competitor — bare-title canonical-shape page.
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/widgetcase",
            framework: "swiftui",
            title: "WidgetCase | Apple Developer Documentation",
            kind: "struct",
            content: "WidgetCase is a SwiftUI struct."
        )

        let hits = try await idx.search(query: "WidgetCase", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        let topURI = hits.first?.uri
        #expect(
            topURI != "apple-docs://swift/widgetcase",
            "dotted-breadcrumb title must not be force-prepended even when kind=unknown"
        )
    }

    // MARK: - 2. canonical-shape rows are still prepended

    @Test("kind=protocol with bare title IS force-prepended (URLSession real-world shape)")
    func protocolKindStillPrepended() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // foundation/urlsessionish — canonical protocol page.
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://foundation/urlsessionish",
            framework: "foundation",
            title: "URLSessionish | Apple Developer Documentation",
            kind: "protocol",
            content: "An object that coordinates a group of related, network data transfer tasks."
        )
        // swiftui/urlsessionish — kind=property, must lose under #630.
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/urlsessionish",
            framework: "swiftui",
            title: "urlSessionish",
            kind: "property",
            content: "var urlSessionish: URLSessionish — a property called urlSessionish."
        )

        let hits = try await idx.search(query: "URLSessionish", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(
            hits.first?.uri == "apple-docs://foundation/urlsessionish",
            "protocol-kind canonical page must surface above property-kind sibling"
        )
    }

    @Test("kind=unknown with bare title still prepends (Codable safety-net shape)")
    func unknownKindWithBareTitleStillPrepends() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Mirrors swift/codable in v1.1.0: kind=unknown but title is
        // `Codable | Apple Developer Documentation`. The pre-#630
        // prepend caught this case and we must not regress.
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/widgetlike",
            framework: "swift",
            title: "Widgetlike | Apple Developer Documentation",
            kind: "unknown",
            content: "A type alias bridging two related Widget shapes."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://uikit/uiwidgetlike-property",
            framework: "uikit",
            title: "widgetlike",
            kind: "property",
            content: "var widgetlike: Bool — a property called widgetlike."
        )

        let hits = try await idx.search(query: "Widgetlike", source: "apple-docs", limit: 5)
        #expect(
            hits.first?.uri == "apple-docs://swift/widgetlike",
            "kind=unknown + bare title must still get the canonical-prepend boost"
        )
    }

    // MARK: - 3. method-kind variants are rejected

    @Test("kind=instance method (with whitespace variant) is rejected")
    func instanceMethodKindRejected() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://foundation/spacecase",
            framework: "foundation",
            title: "spacecase",
            kind: "instance method",
            content: "func spacecase() — an instance method."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/spacecase-overview",
            framework: "swiftui",
            title: "Spacecase | Apple Developer Documentation",
            kind: "class",
            content: "Spacecase is a class in SwiftUI overview."
        )

        let hits = try await idx.search(query: "Spacecase", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(
            hits.first?.uri != "apple-docs://foundation/spacecase",
            "kind='instance method' (whitespace variant) must be rejected"
        )
    }
}
