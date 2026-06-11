@testable import CLI
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import Testing

// MARK: - #935 end-to-end pluggability proof

//
// The empirical proof of the Source Independence Day claim (#919):
// adding a new content source is a composition-root-only change.
// This test file constructs a fake "wwdc-transcripts" source from
// scratch (descriptor + strategy + indexer), wires it through the
// production Search pipeline at a test composition root, indexes a
// 3-document fixture corpus into a tmp `search.db`, and asserts the
// fixture documents are searchable via `Search.Index.search`.
//
// Critical proof: this PR adds ONLY this new test file. The diff
// stat against `Packages/Sources/` is `+0 / -0`. No edits to:
//   - `Search.SourceRegistry` (deleted in #934 Step 3b)
//   - `Search.Source` (the struct stays a string-wrapping value;
//     `Search.Source(rawValue: "wwdc-transcripts")` constructs
//     without any registry update)
//   - `SearchSQLite/Search.SourceIndexer.swift` (no new indexer
//     concrete added; the fake's `Search.SourceIndexer` conformer
//     lives inline in this test file)
//   - `SearchStrategies/Search.MakeDefaultStrategies.swift` (deleted
//     in #933)
//   - any other source's strategy or indexer
//
// The composition root happens HERE (in the test). The CLI's
// production composition root is unchanged.

// MARK: - Fake "wwdc-transcripts" source

/// Inline fake `Search.SourceIndexingStrategy` for a hypothetical
/// `wwdc-transcripts` source. Indexes a 3-document corpus into the
/// supplied search index via the production `indexDocument(...)` API
/// (the same surface real strategies use).
private struct FakeWWDCStrategy: Search.SourceIndexingStrategy {
    let source = "wwdc-transcripts"
    let logger: any LoggingModels.Logging.Recording

    /// Corpus fixture: 3 distinct WWDC transcript "documents" with
    /// distinct content terms so the search assertion can route each.
    static let fixture: [Search.IndexDocumentParams] = [
        Search.IndexDocumentParams(
            uri: "wwdc-transcripts://session/2024-101",
            source: "wwdc-transcripts",
            framework: "SwiftUI",
            language: "swift",
            title: "Platforms State of the Union",
            content: "Welcome to WWDC. This session covers SwiftUI animations and the new declarative APIs.",
            filePath: "wwdc-101.json",
            contentHash: "fixture-hash-101",
            lastCrawled: Date(timeIntervalSince1970: 1700000000),
            sourceType: "wwdc-transcripts",
            packageId: nil,
            jsonData: nil
        ),
        Search.IndexDocumentParams(
            uri: "wwdc-transcripts://session/2024-238",
            source: "wwdc-transcripts",
            framework: "Foundation",
            language: "swift",
            title: "Meet Swift Testing",
            content: "Swift Testing is the new framework that replaces XCTest for unit test authoring.",
            filePath: "wwdc-238.json",
            contentHash: "fixture-hash-238",
            lastCrawled: Date(timeIntervalSince1970: 1700000000),
            sourceType: "wwdc-transcripts",
            packageId: nil,
            jsonData: nil
        ),
        Search.IndexDocumentParams(
            uri: "wwdc-transcripts://session/2024-410",
            source: "wwdc-transcripts",
            framework: "Concurrency",
            language: "swift",
            title: "Embracing Swift concurrency",
            content: "Async / await and structured concurrency unlock safer parallelism for iOS apps.",
            filePath: "wwdc-410.json",
            contentHash: "fixture-hash-410",
            lastCrawled: Date(timeIntervalSince1970: 1700000000),
            sourceType: "wwdc-transcripts",
            packageId: nil,
            jsonData: nil
        ),
    ]

    func indexItems(
        into index: any Search.Database & Search.IndexWriter,
        progress _: (any Search.IndexingProgressReporting)?
    ) async throws -> Search.IndexStats {
        var indexed = 0
        for doc in Self.fixture {
            try await index.indexDocument(doc)
            indexed += 1
        }
        logger.output("wwdc-transcripts strategy indexed \(indexed) fixture documents")
        return Search.IndexStats(source: source, indexed: indexed, skipped: 0)
    }
}

/// Inline fake `Search.SourceIndexer` for the wwdc-transcripts
/// source. Demonstrates the `indexItem` dispatch path that #932
/// added; not actually exercised by the strategy above (which uses
/// `indexDocument` directly), but pins that a new source CAN bring
/// its own `SourceIndexer` conformer without touching SearchSQLite.
private struct FakeWWDCIndexer: Search.SourceIndexer {
    let sourceID = "wwdc-transcripts"
    let displayName = "WWDC Transcripts"

    func validate(_: Search.SourceItem) -> Bool {
        true
    }

    func extractCode(from _: Search.SourceItem) -> Search.ExtractedContent {
        .empty
    }

    func preprocess(_ item: Search.SourceItem) -> Search.SourceItem {
        item
    }

    func postprocess(_: Search.SourceItem) {}
}

/// Inline fake `Search.SourceDefinition` for the wwdc-transcripts
/// source. Pluggability claim: this descriptor lives entirely in the
/// test file. The production composition root in
/// `CLIImpl.makeProductionSourceRegistry()` is NOT edited; the test's
/// own composition root assembles a `Search.SourceLookup` that
/// includes both the production 8 + this fake 1.
private extension Search.SourceDefinition {
    static let fakeWWDC = Search.SourceDefinition(
        id: "wwdc-transcripts",
        displayName: "WWDC Transcripts",
        emoji: "🎥",
        properties: Search.SourceProperties(
            authority: 1.0,
            freshness: 0.5,
            comprehensiveness: 0.6,
            codeExamples: 0.7,
            hasAvailability: 0.4,
            designFocus: 0.3,
            languageFocus: 0.4,
            searchQuality: 0.7
        ),
        intents: [.howTo, .conceptual]
    )
}

// MARK: - End-to-end test

@Suite("#935 end-to-end source pluggability proof (fake WWDC source)")
struct Issue935EndToEndPluggabilityTests {
    @Test("a brand-new source plugs in via composition-root assembly and is searchable end-to-end")
    func newSourceSearchableEndToEnd() async throws {
        // Test composition root: tmp search.db + lookup carrying the
        // fake WWDC source + indexer dict carrying the fake indexer
        // (proves both the #932 indexer-dict and #934 lookup surfaces
        // accept new sources without any production-side edit).
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue935-end2end-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let logger = LoggingModels.Logging.NoopRecording()
        let testLookup = Search.SourceLookup(definitions: [.fakeWWDC])

        let searchIndex = try await Search.Indexer(
            dbPath: dbPath,
            logger: logger,
            indexers: ["wwdc-transcripts": FakeWWDCIndexer()],
            sourceLookup: testLookup
        )
        defer { Task { await searchIndex.disconnect() } }

        // Wire the strategy + run buildIndex via the production
        // `Search.IndexBuilder`. No real CLI command code is invoked;
        // we exercise only the seams that #932 + #933 + #934 lifted to
        // the composition root.
        let strategy = FakeWWDCStrategy(logger: logger)
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            strategies: [strategy],
            logger: logger
        )
        try await builder.buildIndex()

        // Assertion 1: every fixture document is indexed.
        let docCount = try await searchIndex.documentCount()
        #expect(docCount == FakeWWDCStrategy.fixture.count, "expected \(FakeWWDCStrategy.fixture.count) indexed; got \(docCount)")

        // Assertion 2: fixture documents are searchable.
        let swiftUIResults = try await searchIndex.search(query: "SwiftUI", limit: 10)
        #expect(swiftUIResults.contains { $0.uri == "wwdc-transcripts://session/2024-101" }, "Platforms State of the Union (SwiftUI) should be searchable")
        let testingResults = try await searchIndex.search(query: "Swift Testing", limit: 10)
        #expect(testingResults.contains { $0.uri == "wwdc-transcripts://session/2024-238" }, "Meet Swift Testing should be searchable")
        let concurrencyResults = try await searchIndex.search(query: "concurrency", limit: 10)
        #expect(concurrencyResults.contains { $0.uri == "wwdc-transcripts://session/2024-410" }, "Embracing Swift concurrency should be searchable")

        // Assertion 3: every fixture's source field is "wwdc-transcripts"
        // and round-trips through the result's `source` column. This
        // pins that the new source's identity reaches the FTS row.
        for doc in swiftUIResults where doc.uri.hasPrefix("wwdc-transcripts://") {
            #expect(doc.source == "wwdc-transcripts")
        }

        // Assertion 4: the test SourceLookup recognises the fake
        // source via the same instance methods the production ranking
        // path uses. Pins that descriptor lookup is data-driven, not
        // hardcoded.
        let fakeSource = Search.Source(rawValue: "wwdc-transcripts")
        #expect(testLookup.isRegistered(fakeSource))
        #expect(testLookup.displayName(for: fakeSource) == "WWDC Transcripts")
        #expect(testLookup.emoji(for: fakeSource) == "🎥")
        #expect(testLookup.properties(for: "wwdc-transcripts")?.searchQuality == 0.7)
    }

    @Test("the built-in production sources stay reachable through the production composition-root lookup; the fake is NOT in production")
    func productionSourcesAreUntouched() {
        // Pins that this PR's fake source does NOT leak into the
        // production composition root. Post-#1025 (Phase 1I.a of
        // #1007), the production `Search.SourceLookup` is derived
        // from the per-source registry rather than the dissolved
        // `makeProductionSourceLookup` inline literal list.
        let production = Search.SourceLookup(
            definitions: CLIImpl.makeProductionSourceRegistry().allEnabled.map(\.definition)
        )
        let productionIds = Set(production.allIDs)
        #expect(productionIds.isSuperset(of: [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.packages,
        ]))
        #expect(!productionIds.contains("wwdc-transcripts"), "Fake WWDC source must not have leaked into production")
        // Symmetrically: the fake lookup constructed in the end-to-end
        // test does NOT contain the production sources.
        let testLookup = Search.SourceLookup(definitions: [.fakeWWDC])
        #expect(!testLookup.allIDs.contains("apple-docs"))
        #expect(testLookup.allIDs == ["wwdc-transcripts"])
    }

    @Test("Independence Day exit criterion: this PR's diff stat against Packages/Sources/ is +0 / -0")
    func noProductionEditsClaim() {
        // This test is a doc anchor, not a CI-enforceable mechanical
        // check (that would require shelling out to git from within
        // Swift Testing). The PR body carries the diff stat the
        // critic verifies at review time. This stub keeps the claim
        // visible alongside the other assertions.
        //
        // Run on the PR branch:
        //   git diff develop --stat Packages/Sources/
        //   git diff develop --stat Packages/Tests/
        //
        // Expected: Sources/ shows zero lines changed; Tests/ shows
        // only this file added.
        #expect(Bool(true), "see PR body for the diff-stat anchor")
    }
}
