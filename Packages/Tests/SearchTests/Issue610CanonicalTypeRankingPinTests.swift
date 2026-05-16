import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

/// Regression-pin for [#610](https://github.com/mihaelamj/cupertino/issues/610)
/// + main's 2026-05-16 post-v1.2.0-reindex audit (15-canonical-type set).
///
/// `CanonicalTypeRankingTests` covers 7 of the 15 main verified (URL,
/// URLSession, Color, View, Data, String, Array). This file pins the
/// remaining 8 so the BUG 1 cure can't regress on any of them. Adding
/// every canonical type to the regression battery follows the John Carmack
/// rule: when a class of bug is eliminated, lock in the entire class with
/// tests so it can't return.
///
/// Each test seeds a temp DB with:
/// - 1 canonical apple-docs page (the type itself).
/// - 1-3 realistic collision peers (sub-symbols, properties, framework
///   shadows) that previously out-ranked the canonical page on the v1.1.0
///   bundle.
///
/// Pre-cure (v1.1.0): query returns a collision peer first.
/// Post-cure (HEURISTIC 1 / 1.5 / 1.6 + per-column BM25F weights): query
/// returns the canonical page at top-1.
///
/// Runs entirely against in-memory FTS5 fixtures. No corpus rebuild needed.
@Suite("#610 canonical-type ranking pin — main's 15-type audit set")
struct Issue610CanonicalTypeRankingPinTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue610-pin-\(UUID().uuidString).db")
    }

    private static func indexPage(
        on idx: Search.Index,
        uri: String,
        framework: String,
        title: String,
        content: String
    ) async throws {
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: uri,
            source: "apple-docs",
            framework: framework,
            title: title,
            content: content,
            filePath: "/tmp/\(framework)-\(UUID().uuidString)",
            contentHash: UUID().uuidString,
            lastCrawled: Date()
        ))
    }

    // MARK: - SwiftUI canonical types

    @Test("NavigationStack → SwiftUI canonical beats ToolbarRole sub-symbol")
    func navigationStackBeatsToolbarRoleSubSymbol() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swiftui/navigationstack",
            framework: "swiftui",
            title: "NavigationStack",
            content: "A view that displays a root view and enables you to present additional views over the root view."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swiftui/toolbarrole/navigationstack",
            framework: "swiftui",
            title: "navigationStack",
            content: "A toolbar role that emphasizes a navigation stack-style appearance for the toolbar."
        )

        let hits = try await idx.search(query: "NavigationStack", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swiftui/navigationstack")
    }

    @Test("Font → SwiftUI Font beats EnvironmentValues.font property")
    func fontBeatsEnvironmentValuesProperty() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swiftui/font",
            framework: "swiftui",
            title: "Font",
            content: "An environment-dependent font. SwiftUI provides a collection of built-in fonts and supports custom font configuration."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swiftui/environmentvalues/font",
            framework: "swiftui",
            title: "font",
            content: "The default font of this environment. Read this value to access the current font set on this environment."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://uikit/uifont",
            framework: "uikit",
            title: "UIFont",
            content: "An object that provides access to the font's characteristics. UIFont reports a font's family, face, and size."
        )

        let hits = try await idx.search(query: "Font", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swiftui/font")
    }

    @Test("List → SwiftUI List beats DragDropPreviewsFormation.list sub-symbol")
    func listBeatsDragDropSubSymbol() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swiftui/list",
            framework: "swiftui",
            title: "List",
            content: "A container that presents rows of data arranged in a single column, optionally providing the ability to select one or more members."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swiftui/dragdroppreviewsformation/list",
            framework: "swiftui",
            title: "list",
            content: "A formation that arranges drag-drop previews into a list-style stack."
        )

        let hits = try await idx.search(query: "List", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swiftui/list")
    }

    // MARK: - Foundation canonical types

    @Test("JSONDecoder → Foundation canonical beats no real peers")
    func jsonDecoderIsCanonical() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://foundation/jsondecoder",
            framework: "foundation",
            title: "JSONDecoder",
            content: "An object that decodes instances of a data type from JSON objects. Foundation provides JSONDecoder to translate JSON into Swift data."
        )
        // Sub-symbol peers within JSONDecoder (decode methods etc).
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://foundation/jsondecoder/decode(_:from:)",
            framework: "foundation",
            title: "decode(_:from:)",
            content: "Returns a value of the type you specify, decoded from a JSON object. JSONDecoder uses this method to translate JSON into Swift."
        )

        let hits = try await idx.search(query: "JSONDecoder", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://foundation/jsondecoder")
    }

    // MARK: - Swift stdlib protocols

    @Test("Hashable → Swift protocol beats Set / Dictionary conformance mentions")
    func hashableProtocolBeatsConformanceMentions() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/hashable",
            framework: "swift",
            title: "Hashable",
            content: "A type that can be hashed into a Hasher to produce an integer hash value. You can use any type that conforms to Hashable as a Set value or Dictionary key."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/set",
            framework: "swift",
            title: "Set",
            content: "An unordered collection of unique elements. Elements must conform to Hashable for the Set to function. Set provides the standard hashable-element semantics."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/dictionary",
            framework: "swift",
            title: "Dictionary",
            content: "A collection whose elements are key-value pairs. Keys must conform to Hashable. Dictionary uses Hashable to deduplicate entries."
        )

        let hits = try await idx.search(query: "Hashable", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/hashable")
    }

    @Test("Sendable → Swift protocol beats sub-symbol checked-Sendable peers")
    func sendableProtocolBeatsCheckedSendable() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/sendable",
            framework: "swift",
            title: "Sendable",
            content: "A type whose values can safely be passed across concurrency domains. Sendable types provide the foundation of data-race-free concurrent code."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/uncheckedsendable",
            framework: "swift",
            title: "@unchecked Sendable",
            content: "Declare a Sendable conformance as unchecked when you've manually verified the type is safe. The compiler won't enforce Sendable requirements."
        )

        let hits = try await idx.search(query: "Sendable", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/sendable")
    }

    @Test("Codable → Swift typealias beats individual Encodable/Decodable mentions")
    func codableBeatsEncodableDecodableMentions() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/codable",
            framework: "swift",
            title: "Codable",
            content: "A type that can convert itself into and out of an external representation. Codable is a typealias for the Encodable and Decodable protocols."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/encodable",
            framework: "swift",
            title: "Encodable",
            content: "A type that can encode itself to an external representation. Encodable is half of the Codable typealias."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/decodable",
            framework: "swift",
            title: "Decodable",
            content: "A type that can decode itself from an external representation. Decodable is half of the Codable typealias."
        )

        let hits = try await idx.search(query: "Codable", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/codable")
    }

    @Test("Equatable → Swift protocol beats sub-symbol == operator pages")
    func equatableProtocolBeatsEqualsOperatorPages() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/equatable",
            framework: "swift",
            title: "Equatable",
            content: "A type that can be compared for value equality. Use the == operator to compare two Equatable values, or != to compare them for inequality."
        )
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://swift/equatable/==(_:_:)",
            framework: "swift",
            title: "==(_:_:)",
            content: "Returns a Boolean value indicating whether two values are equal. The == operator is the canonical Equatable conformance member."
        )

        let hits = try await idx.search(query: "Equatable", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/equatable")
    }

    // MARK: - The full set as a single parameterised pin

    /// Runs all 15 canonical types from main's post-v1.2.0-reindex audit
    /// as one parameterised test. Each entry seeds a canonical page + the
    /// most-likely collision peer and verifies the canonical wins.
    ///
    /// This is the regression-pin for the BUG 1 cure: when one of the 15
    /// breaks, this test names it without manual triage.
    @Test(
        "Canonical-type pin matrix (15-type post-reindex audit set)",
        arguments: [
            ("NavigationStack", "apple-docs://swiftui/navigationstack", "swiftui"),
            ("View", "apple-docs://swiftui/view", "swiftui"),
            ("Color", "apple-docs://swiftui/color", "swiftui"),
            ("Font", "apple-docs://swiftui/font", "swiftui"),
            ("List", "apple-docs://swiftui/list", "swiftui"),
            ("Hashable", "apple-docs://swift/hashable", "swift"),
            ("Sendable", "apple-docs://swift/sendable", "swift"),
            ("Codable", "apple-docs://swift/codable", "swift"),
            ("Equatable", "apple-docs://swift/equatable", "swift"),
            ("URL", "apple-docs://foundation/url", "foundation"),
            ("URLSession", "apple-docs://foundation/urlsession", "foundation"),
            ("JSONDecoder", "apple-docs://foundation/jsondecoder", "foundation"),
            ("Data", "apple-docs://foundation/data", "foundation"),
            ("String", "apple-docs://swift/string", "swift"),
            ("Array", "apple-docs://swift/array", "swift"),
        ]
    )
    func canonicalTypePinMatrix(query: String, expectedURI: String, framework: String) async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Canonical page — short, encyclopedic, BM25 should win on the
        // boosted title path.
        try await Self.indexPage(
            on: idx,
            uri: expectedURI,
            framework: framework,
            title: query,
            content: "Canonical Apple documentation page for \(query). \(query) is the top-level type referenced by SDK users."
        )
        // Collision peer — short property-style page whose title shadows
        // the canonical. Pre-cure this would have out-ranked the canonical
        // because the type name appears multiple times in a small body.
        try await Self.indexPage(
            on: idx,
            uri: "apple-docs://shadowframework/somecontainer/\(query.lowercased())",
            framework: "shadowframework",
            title: query.lowercased(),
            content: "A property typed \(query) on a container type. The \(query) accessor returns the contained \(query). Use \(query) to read."
        )

        let hits = try await idx.search(query: query, source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty, "query \"\(query)\" returned no hits")
        #expect(
            hits.first?.uri == expectedURI,
            "query \"\(query)\" expected top-1 \(expectedURI); got \(hits.first?.uri ?? "(nil)")"
        )
    }
}
