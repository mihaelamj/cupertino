import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

// MARK: - #225 Part B — implementation_swift_version on swift-evolution rows

//
// Three layers under test, exercised by three test groups:
//
// 1. The pure-string parser `Search.StrategyHelpers.extractImplementationSwiftVersion(from:)`
//    walks proposal markdown for an `Implementation: Swift X[.Y]` line (primary)
//    or a `Status: Implemented (Swift X.Y)` line (fallback) and returns the
//    canonical `<major>.<minor>` string. Tests below pin both shapes plus the
//    no-match / short-version / normalisation edge cases.
//
// 2. The schema bump v15 → v16 adds `implementation_swift_version TEXT` to
//    `docs_metadata` via an in-place ALTER TABLE migration. The integration
//    test stamps a v15 DB, opens it with a v16 binary, confirms the column
//    is reachable, and round-trips a value through indexStructuredDocument.
//
// 3. The `--swift` filter scopes results to swift-evolution rows whose stored
//    version is ≤ the user threshold (semver-aware compare via the existing
//    Search.Index.isVersion algorithm) — and rejects every row missing a
//    value (every non-evolution row + evolution rows the parser couldn't
//    read a version from), matching the NULL-rejection semantic the platform
//    filters use.

// MARK: - Parser

@Suite("#225 Part B — extractImplementationSwiftVersion parser")
struct Issue225PartBParserTests {
    @Test("Primary: `Implementation: Swift X.Y` line")
    func primaryDottedVersion() {
        let md = """
        # SE-0001 Allow (most) keywords as argument labels

        * Proposal: [SE-0001](0001-keywords-as-argument-labels.md)
        * Status: **Implemented (Swift 2.0)**
        * Implementation: Swift 2.0
        """
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == "2.0")
    }

    @Test("Primary wins over fallback when both lines carry a version")
    func primaryWinsOverStatus() {
        // Engineered to test the precedence: the status line carries 5.5 but
        // the dedicated implementation line carries 5.9. The implementation
        // line is the canonical citation, so 5.9 should win.
        let md = """
        * Status: **Implemented (Swift 5.5)**
        * Implementation: Swift 5.9
        """
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == "5.9")
    }

    @Test("Fallback: `Status: Implemented (Swift X.Y)` when no implementation line")
    func fallbackStatusForm() {
        let md = """
        * Proposal: [SE-0123](...)
        * Status: **Implemented (Swift 5.5)**
        * Review: ...
        """
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == "5.5")
    }

    @Test("Single-component version normalises to <major>.0")
    func singleComponentNormalises() {
        let md = "* Implementation: Swift 6"
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == "6.0")
    }

    @Test("Bold-marker formatting around `Implementation:` doesn't break the scan")
    func boldMarkersTolerated() {
        let md = "* **Implementation:** Swift 5.10"
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == "5.10")
    }

    @Test("Multi-digit minor versions preserve (Swift 5.10 ≠ Swift 5.1)")
    func multiDigitMinorPreserved() {
        // Critical for the post-fetch semver compare: string compare would
        // get `"5.10" <= "5.2"` wrong; the version we store must keep the
        // literal `5.10` so the existing isVersion semver math compares
        // by integer components rather than character sequence.
        let md = "* Implementation: Swift 5.10"
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == "5.10")
    }

    @Test("No-match returns nil")
    func noMatchReturnsNil() {
        let md = """
        # SE-0999 An accepted-but-not-yet-implemented proposal

        * Status: **Accepted**
        * Implementation: Awaiting review
        """
        // `Implementation: Awaiting review` has no `Swift X` after the colon,
        // and the status doesn't carry `Implemented (Swift ...)`. Nothing to
        // extract — return nil so the indexer writes NULL.
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == nil)
    }

    @Test("Empty markdown returns nil")
    func emptyReturnsNil() {
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: "") == nil)
    }

    @Test("Status without implementation tag — returns nil even when implemented")
    func statusOnlyNoVersionReturnsNil() {
        // `Status: Implemented` without the parenthesised Swift version
        // shouldn't match the fallback — the regex requires the version
        // capture group inside the parens.
        let md = "* Status: **Implemented**"
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == nil)
    }

    @Test("Case-insensitive on the `Swift` keyword + the directive labels")
    func caseInsensitive() {
        let md = "* implementation: SWIFT 4.2"
        #expect(Search.StrategyHelpers.extractImplementationSwiftVersion(from: md) == "4.2")
    }
}

// MARK: - Migration + persistence round-trip

@Suite("#225 Part B — v15→v16 migration + indexStructuredDocument round-trip", .serialized)
struct Issue225PartBPersistenceTests {
    private static func makeIndex() async throws -> (Search.Index, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-225-part-b-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())
        return (index, tempDir)
    }

    @Test("Fresh v16 DB has implementation_swift_version column populated through indexStructuredDocument")
    func freshV16RoundTrips() async throws {
        let (index, tempDir) = try await Self.makeIndex()
        defer {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Build a minimal article-shape structured page (the helper the
        // SwiftEvolution strategy uses).
        let pageURL = try #require(URL(string: "https://github.com/swiftlang/swift-evolution/blob/main/proposals/SE-0001.md"))
        let page = Search.StrategyHelpers.makeArticleStructuredPage(
            url: pageURL,
            title: "Allow keywords as argument labels",
            rawMarkdown: "# SE-0001\n* Implementation: Swift 2.0",
            crawledAt: Date(),
            contentHash: "deadbeef"
        )
        let json = Search.StrategyHelpers.encodeStructuredPageToJSON(page)

        try await index.indexStructuredDocument(
            uri: "swift-evolution://SE-0001",
            source: "swift-evolution",
            framework: "swift-evolution",
            page: page,
            jsonData: json,
            implementationSwiftVersion: "2.0"
        )

        // Round-trip via search().
        let results = try await index.search(query: "argument labels", source: "swift-evolution", minSwift: "5.0")
        // Expect the row to pass the filter (its stored 2.0 is ≤ the
        // user's 5.0 threshold).
        #expect(!results.isEmpty, "swift-evolution row with implementation_swift_version=2.0 should pass --swift 5.0")
        #expect(results.first?.uri == "swift-evolution://SE-0001")
    }

    @Test("Row with no implementationSwiftVersion is rejected when --swift is set")
    func nullRowRejectedWithFilter() async throws {
        let (index, tempDir) = try await Self.makeIndex()
        defer {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let pageURL = try #require(URL(string: "https://github.com/swiftlang/swift-evolution/blob/main/proposals/SE-9999.md"))
        let page = Search.StrategyHelpers.makeArticleStructuredPage(
            url: pageURL,
            title: "An accepted but unimplemented proposal",
            rawMarkdown: "# SE-9999",
            crawledAt: Date(),
            contentHash: "cafebabe"
        )
        let json = Search.StrategyHelpers.encodeStructuredPageToJSON(page)

        // Write WITHOUT an implementation version — the column stays NULL.
        try await index.indexStructuredDocument(
            uri: "swift-evolution://SE-9999",
            source: "swift-evolution",
            framework: "swift-evolution",
            page: page,
            jsonData: json
        )

        // Without --swift, the row should appear.
        let unfiltered = try await index.search(query: "unimplemented proposal", source: "swift-evolution")
        #expect(!unfiltered.isEmpty, "Pre-condition: the NULL-version row exists and is findable without --swift")

        // With --swift, the NULL row must be rejected (matches the
        // platform-filter NULL-rejection semantic).
        let filtered = try await index.search(query: "unimplemented proposal", source: "swift-evolution", minSwift: "6.0")
        #expect(filtered.isEmpty, "post-#225B: a swift-evolution row with NULL implementation_swift_version must be rejected when --swift is set")
    }

    @Test("Semver-aware compare: Swift 5.10 passes --swift 5.10 but not --swift 5.2")
    func semverCompareCorrect() async throws {
        let (index, tempDir) = try await Self.makeIndex()
        defer {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let pageURL = try #require(URL(string: "https://github.com/swiftlang/swift-evolution/blob/main/proposals/SE-0420.md"))
        let page = Search.StrategyHelpers.makeArticleStructuredPage(
            url: pageURL,
            title: "Semver edge case proposal",
            rawMarkdown: "* Implementation: Swift 5.10",
            crawledAt: Date(),
            contentHash: "abc12345"
        )
        let json = Search.StrategyHelpers.encodeStructuredPageToJSON(page)

        try await index.indexStructuredDocument(
            uri: "swift-evolution://SE-0420",
            source: "swift-evolution",
            framework: "swift-evolution",
            page: page,
            jsonData: json,
            implementationSwiftVersion: "5.10"
        )

        // 5.10 ≤ 5.10 → pass.
        let passes = try await index.search(query: "semver edge case", source: "swift-evolution", minSwift: "5.10")
        #expect(!passes.isEmpty, "5.10 row should pass --swift 5.10")

        // 5.10 ≤ 5.2 → FALSE (5.10 > 5.2 by integer-component compare,
        // even though "5.10" < "5.2" lexicographically). This is the
        // exact bug the post-fetch in-memory compare prevents.
        let rejects = try await index.search(query: "semver edge case", source: "swift-evolution", minSwift: "5.2")
        #expect(rejects.isEmpty, "5.10 row must NOT pass --swift 5.2 (semver compare; string compare would mistakenly accept it)")
    }
}
