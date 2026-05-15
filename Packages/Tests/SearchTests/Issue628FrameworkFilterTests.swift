import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

/// Regression suite for [#628](https://github.com/mihaelamj/cupertino/issues/628).
///
/// The `--framework` flag had three independent bugs:
///
/// 1. **A — canonical-prepend leak.** The `fetchCanonicalTypePages` safety
///    net (#256 / #610 Class A) probed all three top-tier frameworks
///    (`swift`, `swiftui`, `foundation`) regardless of the caller's filter,
///    so `cupertino search View --framework foundation` returned
///    `apple-docs://swiftui/view` at rank -2000.
///
/// 2. **B — bogus value silently accepted.** When `resolveFrameworkIdentifier`
///    returned nil (input didn't match any identifier, import name, display
///    name, or synonym), `Search.Index.search` proceeded with no framework
///    filter at all. `cupertino search View --framework banana` read as if
///    the flag wasn't there.
///
/// 3. **C — unified (no `--source`) path dropped the filter entirely.** The
///    `DocsSourceCandidateFetcher` adapter that the SmartQuery fan-out
///    uses didn't take a `framework` parameter; the source-scoped path
///    (`--source apple-docs`) honoured `--framework` but the default path
///    didn't. Reported by user as a hig-vs-apple-docs discrepancy.
///
/// The fix touches three call sites:
///
/// - `fetchCanonicalTypePages` now takes `framework: String?` and skips
///   probes whose framework doesn't match.
/// - `Search.Index.search` validates non-empty `framework` against the
///   alias table and throws `Search.Error.invalidQuery` on miss.
/// - `DocsSourceCandidateFetcher` takes `framework: String?` and threads
///   it to `searchIndex.search`; the CLI's `runUnifiedSearch` validates
///   the input once before calling `SmartQuery.answer` (per-fetcher
///   throws are silently swallowed inside the fan-out, so validation
///   has to happen earlier).
@Suite("#628 --framework filter is honoured everywhere", .serialized)
struct Issue628FrameworkFilterTests {
    // MARK: - Helpers

    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue628-\(UUID().uuidString).db")
    }

    /// Index a row with explicit framework + kind in the wrapper JSON.
    /// Matches the shape used by `Issue610ClassARankingTests` so the
    /// safety-net canonical-prepend fires.
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
        // The alias table is what `resolveFrameworkIdentifier` consults;
        // populate it explicitly so test fixtures behave like real corpus.
        try await idx.registerFrameworkAlias(
            identifier: framework,
            displayName: framework
        )
    }

    // MARK: - A. canonical-prepend honours --framework

    @Test("A: canonical-prepend skips non-matching frameworks under --framework filter")
    func canonicalPrependRespectsFrameworkFilter() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Two canonical-shape rows that the safety net would normally prepend:
        // the SwiftUI View protocol and a Foundation-side stand-in. With
        // `--framework foundation` the SwiftUI row MUST NOT appear.
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
            uri: "apple-docs://foundation/view",
            framework: "foundation",
            title: "View | Apple Developer Documentation",
            kind: "struct",
            content: "A Foundation View placeholder used in test fixtures only."
        )

        let hits = try await idx.search(
            query: "View",
            source: "apple-docs",
            framework: "foundation",
            limit: 10
        )

        // Every returned row is scoped to foundation. Pre-fix, the SwiftUI
        // safety-net prepend would inject `apple-docs://swiftui/view` at
        // rank 2000, violating the user's explicit filter.
        #expect(hits.allSatisfy { $0.framework == "foundation" })
        #expect(hits.contains { $0.uri == "apple-docs://foundation/view" })
        #expect(!hits.contains { $0.uri == "apple-docs://swiftui/view" })
    }

    @Test("A: canonical-prepend still fires when --framework matches the canonical framework")
    func canonicalPrependFiresWhenFrameworkMatches() async throws {
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
        // A property-shaped peer in the same framework, to confirm the
        // canonical-prepend still surfaces the protocol page even with
        // the framework filter active.
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/views",
            framework: "swiftui",
            title: "views",
            kind: "property",
            content: "The array of views owned by the controller."
        )

        let hits = try await idx.search(
            query: "View",
            source: "apple-docs",
            framework: "swiftui",
            limit: 5
        )
        #expect(hits.first?.uri == "apple-docs://swiftui/view")
    }

    // MARK: - B. bogus framework rejected loudly

    @Test("B: --framework banana throws Search.Error.invalidQuery")
    func bogusFrameworkThrows() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Seed the alias table with one real framework so the lookup has
        // a populated table to consult.
        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/view",
            framework: "swiftui",
            title: "View",
            kind: "protocol",
            content: "A type that represents part of your app's user interface."
        )

        await #expect(throws: Search.Error.self) {
            _ = try await idx.search(
                query: "View",
                source: "apple-docs",
                framework: "banana",
                limit: 5
            )
        }
    }

    @Test("B: empty --framework treats filter as absent (no throw)")
    func emptyFrameworkTreatedAsAbsent() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await Self.indexRow(
            on: idx,
            uri: "apple-docs://swiftui/view",
            framework: "swiftui",
            title: "View",
            kind: "protocol",
            content: "A type that represents part of your app's user interface."
        )

        // Pass an empty string — this is the shape `--framework=` produces
        // and we treat it the same as no flag at all. Must NOT throw.
        let hits = try await idx.search(
            query: "View",
            source: "apple-docs",
            framework: "",
            limit: 5
        )
        #expect(!hits.isEmpty)
    }

    // MARK: - C. unified-path fetcher honours framework

    @Test("C: DocsSourceCandidateFetcher passes --framework through to apple-docs search")
    func unifiedDocsFetcherRespectsFramework() async throws {
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
            uri: "apple-docs://foundation/view",
            framework: "foundation",
            title: "View | Apple Developer Documentation",
            kind: "struct",
            content: "A Foundation View placeholder used in test fixtures only."
        )

        let fetcher = Search.DocsSourceCandidateFetcher(
            searchIndex: idx,
            source: "apple-docs",
            framework: "foundation"
        )
        let batch = try await fetcher.fetch(question: "View", limit: 10)
        let identifiers = batch.map(\.identifier)

        // Foundation hit must be present, SwiftUI hit must not.
        #expect(identifiers.contains("apple-docs://foundation/view"))
        #expect(!identifiers.contains("apple-docs://swiftui/view"))
    }

    @Test("C: DocsSourceCandidateFetcher drops --framework for non-apple sources (no zero-out)")
    func unifiedFetcherDoesNotZeroOutNonAppleSources() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // Stamp a swift-evolution-style row with empty framework (matches
        // the real corpus shape — non-Apple sources don't carry a
        // framework column value).
        try await idx.indexDocument(Search.Index.IndexDocumentParams(
            uri: "swift-evolution://SE-0001",
            source: "swift-evolution",
            framework: "",
            title: "SE-0001: Allow (most) keywords as argument labels",
            content: "Proposal to allow most keywords as argument labels in function calls.",
            filePath: "/tmp/se-0001",
            contentHash: UUID().uuidString,
            lastCrawled: Date()
        ))

        let fetcher = Search.DocsSourceCandidateFetcher(
            searchIndex: idx,
            source: "swift-evolution",
            framework: "foundation"
        )
        let batch = try await fetcher.fetch(question: "argument", limit: 10)

        // The filter must be dropped for swift-evolution (which doesn't
        // carry a meaningful `framework` column); the proposal still hits.
        #expect(batch.contains { $0.identifier == "swift-evolution://SE-0001" })
    }
}
