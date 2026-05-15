import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

/// Regression suite for [#610](https://github.com/mihaelamj/cupertino/issues/610)
/// Class A — the 9 of 14 wrong-winner cases where the canonical Apple type
/// page exists in the corpus but BM25 buries it under a property/method
/// page with the same bare title and stronger term density.
///
/// Pre-fix on the v1.1.0 shipped bundle, `cupertino search Task` returned
/// `URLRequest.task` instead of `Swift.Task`, `cupertino search Identifiable`
/// returned `shazamkit/identifiable-implementations` instead of
/// `Swift.Identifiable`, etc. Two coordinated fixes ship together:
///
/// 1. **HEURISTIC 1.6** — kind-aware tiebreak inside the exact-title-match
///    branch. When two rows both have title matching the query, prefer the
///    one whose `kind` is a canonical type-shape (`class`, `struct`,
///    `enum`, `protocol`, `typealias`, `actor`) over property/method pages.
/// 2. **fetchCanonicalTypePages URI shape** — updated from the pre-#283
///    `apple-docs://<framework>/documentation_<framework>_<query>` form to
///    the post-#283/#589 lossless `apple-docs://<framework>/<query>` form
///    so the safety-net prepend actually fires on the current corpus
///    (where the old shape covers only 3 of 284,518 apple-docs rows).
///
/// These tests use the NEW URI shape to exercise both code paths. The
/// existing `CanonicalTypeRankingTests` exercises the same canonical-vs-
/// peer principle against the OLD URI shape (legacy fixtures still
/// covered by H1 + H1.5).
@Suite("#610 Class A: bare type-name query surfaces canonical page (lossless URI shape)")
struct Issue610ClassARankingTests {
    // MARK: - Helpers

    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue610-classa-\(UUID().uuidString).db")
    }

    /// Stamp a row into the FTS + metadata tables with an explicit `kind`
    /// inlined into the wrapper JSON. The indexer's automatic kind-
    /// inference fallback would otherwise leave most fixtures at `unknown`
    /// which can't exercise HEURISTIC 1.6.
    // swiftlint:disable:next function_parameter_count
    private static func indexRow(
        on idx: Search.Index,
        uri: String,
        framework: String,
        title: String,
        kind: String,
        content: String
    ) async throws {
        // The indexer's nil-jsonData branch (post-#608) auto-builds a
        // wrapper with `rawMarkdown: <content>` but defaults to `kind`
        // from the inference path. Supply an explicit wrapper carrying
        // the test-specific kind so the boost reads the value we want.
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

    // MARK: - The 9 Class A queries

    @Test("Task → Swift.Task class beats URLRequest.task property (post-#283 lossless URI)")
    func taskClassBeatsProperty() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/task",
            framework: "swift",
            title: "Task | Apple Developer Documentation",
            kind: "class",
            content: "A unit of asynchronous work. Use Task to create a top-level concurrent unit of work."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://urlsession/task",
            framework: "urlsession",
            title: "task",
            kind: "property",
            content: "let task: URLSessionTask — The URL session task that this delegate corresponds to."
        )

        let hits = try await idx.search(query: "Task", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/task")
    }

    @Test("View → SwiftUI.View protocol beats appkit/views property")
    func viewProtocolBeatsAppkitProperty() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/view",
            framework: "swiftui",
            title: "View | Apple Developer Documentation",
            kind: "protocol",
            content: "A type that represents part of your app's user interface."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://appkit/views",
            framework: "appkit",
            title: "views",
            kind: "property",
            content: "The array of views owned by the controller."
        )

        let hits = try await idx.search(query: "View", source: "apple-docs", limit: 5)
        #expect(hits.first?.uri == "apple-docs://swiftui/view")
    }

    @Test("String → Swift.String struct beats arkit/ar-strings function")
    func stringStructBeatsFunction() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/string",
            framework: "swift",
            title: "String | Apple Developer Documentation",
            kind: "struct",
            content: "A Unicode string value that is a collection of characters."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://arkit/ar-strings-get-count",
            framework: "arkit",
            title: "string",
            kind: "function",
            content: "Get the count of strings collection. ar_strings_get_count returns the number."
        )

        let hits = try await idx.search(query: "String", source: "apple-docs", limit: 5)
        #expect(hits.first?.uri == "apple-docs://swift/string")
    }

    @Test("Array → Swift.Array struct beats cktooljs/array property")
    func arrayStructBeatsProperty() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/array",
            framework: "swift",
            title: "Array | Apple Developer Documentation",
            kind: "struct",
            content: "An ordered, random-access collection."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://cktooljs/array",
            framework: "cktooljs",
            title: "array",
            kind: "property",
            content: "let array: The array that failed validation."
        )

        let hits = try await idx.search(query: "Array", source: "apple-docs", limit: 5)
        #expect(hits.first?.uri == "apple-docs://swift/array")
    }

    @Test("Hashable → Swift.Hashable protocol beats swiftui sub-symbol")
    func hashableProtocolBeatsSubsymbol() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/hashable",
            framework: "swift",
            title: "Hashable | Apple Developer Documentation",
            kind: "protocol",
            content: "A type that can be hashed into a Hasher to produce an integer hash value."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/matchedtransitionsource",
            framework: "swiftui",
            title: "Hashable",
            kind: "property",
            content: "Conforms MatchedTransitionSource to Hashable using its identifier as the hashable key."
        )

        let hits = try await idx.search(query: "Hashable", source: "apple-docs", limit: 5)
        #expect(hits.first?.uri == "apple-docs://swift/hashable")
    }

    @Test("Equatable → Swift.Equatable protocol beats realitykit equatable-implementations")
    func equatableProtocolBeatsImpls() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/equatable",
            framework: "swift",
            title: "Equatable | Apple Developer Documentation",
            kind: "protocol",
            content: "A type that can be compared for value equality."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://realitykit/equatable-implementations",
            framework: "realitykit",
            title: "Equatable",
            kind: "property",
            content: "RealityKit synthesises Equatable conformances on its public types via these implementations."
        )

        let hits = try await idx.search(query: "Equatable", source: "apple-docs", limit: 5)
        #expect(hits.first?.uri == "apple-docs://swift/equatable")
    }

    @Test("Codable → Swift.Codable typealias beats peer pages")
    func codableTypealiasBeatsPeer() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/codable",
            framework: "swift",
            title: "Codable | Apple Developer Documentation",
            kind: "typealias",
            content: "typealias Codable = Decodable & Encodable — a type that can convert itself into and out of an external representation."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://createml/codable",
            framework: "createml",
            title: "Codable",
            kind: "property",
            content: "Conforming this CreateML model output to Codable preserves the type when serialised."
        )

        let hits = try await idx.search(query: "Codable", source: "apple-docs", limit: 5)
        #expect(hits.first?.uri == "apple-docs://swift/codable")
    }

    @Test("Identifiable → Swift.Identifiable protocol beats shazamkit identifiable-implementations (fetchCanonicalTypePages safety net)")
    func identifiableProtocolBeatsImpls() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/identifiable",
            framework: "swift",
            title: "Identifiable | Apple Developer Documentation",
            kind: "protocol",
            content: "A class of types whose instances hold the value of an entity with stable identity."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://shazamkit/identifiable-implementations",
            framework: "shazamkit",
            title: "Identifiable Implementations | Apple Developer Documentation",
            kind: "unknown",
            content: "ShazamKit collects Identifiable conformances for SHMediaItem and related types here."
        )

        let hits = try await idx.search(query: "Identifiable", source: "apple-docs", limit: 5)
        #expect(hits.first?.uri == "apple-docs://swift/identifiable")
    }

    @Test("Sendable → Swift.Sendable protocol beats peer pages")
    func sendableProtocolBeatsPeer() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swift/sendable",
            framework: "swift",
            title: "Sendable | Apple Developer Documentation",
            kind: "protocol",
            content: "A type whose values can be shared across concurrent contexts safely."
        )
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://realitykit/sendable",
            framework: "realitykit",
            title: "Sendable",
            kind: "property",
            content: "Marks this RealityKit component as Sendable for concurrent use."
        )

        let hits = try await idx.search(query: "Sendable", source: "apple-docs", limit: 5)
        #expect(hits.first?.uri == "apple-docs://swift/sendable")
    }

    // MARK: - Regression anchors

    @Test("Property/method query with no canonical-type peer still returns the property page (not regressed)")
    func nonCanonicalQueryUnchanged() async throws {
        // Query "endImpression" — only the property page exists; the boost
        // should NOT spuriously demote it.
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://storekit/endimpression(-:completionhandler:)",
            framework: "storekit",
            title: "endImpression",
            kind: "method",
            content: "Records the end of an in-app purchase impression event."
        )

        let hits = try await idx.search(query: "endImpression", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://storekit/endimpression(-:completionhandler:)")
    }
}
