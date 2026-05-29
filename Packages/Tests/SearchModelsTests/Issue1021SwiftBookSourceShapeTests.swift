import Foundation
import SearchModels
import SharedConstants
import SwiftBookSource
import Testing

// MARK: - #1021 SwiftBookSource shape pins (view-source pattern)

@Suite("#1021: SwiftBookSource shape pins (view-source)")
struct Issue1021SwiftBookSourceShapeTests {
    @Test("SwiftBookSource.definition carries the swift-book id + intents + intentPriority")
    func definitionShape() {
        let provider = SwiftBookSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        let def = provider.definition
        #expect(def.id == Shared.Constants.SourcePrefix.swiftBook)
        #expect(def.displayName == "The Swift Programming Language")
        #expect(def.emoji == "📖")
        #expect(def.intents == [.languageFeature, .conceptual, .howTo])
        #expect(def.intentPriority[.languageFeature] == 90)
        #expect(def.properties.languageFocus == 1.0)
        #expect(def.properties.codeExamples == 0.9)
    }

    @Test("SwiftBookSource.fetchInfo declares an independent fetch leg (#1093)")
    func fetchInfoIndependent() throws {
        // #1093: swift-book is now an independently-fetchable source.
        // `cupertino fetch --source swift-book` seeds at
        // docs.swift.org/swift-book/ and crawls only the book — no
        // longer dragged through swift-org's combined pass.
        let provider = SwiftBookSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        let info = try #require(provider.fetchInfo)
        #expect(info.sourceID == Shared.Constants.SourcePrefix.swiftBook)
        #expect(info.defaultOutputDirKey == .swiftBook)
        #expect(info.isWebCrawlable == true)
    }

    @Test("SwiftBookSource.corpusDirectoryAlias == nil post-#1093 (no longer a view-source)")
    func corpusDirectoryAliasIsNil() {
        // #1082 made swift-book a view-source over swift-org's
        // corpus via this property. #1093 splits them: swift-book
        // has its own corpus dir, own fetch leg. The alias override
        // is dropped — defaults to nil from the protocol extension.
        let provider = SwiftBookSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        #expect(provider.corpusDirectoryAlias == nil)
    }

    @Test("SwiftBookSource.destinationDB == .swiftBook (post #1038 'diff db for each source'; swift-book owns swift-book.db)")
    func destinationDBExplicit() {
        // Pre-#1038 SwiftBookSource was a view-source: no active
        // strategy, `.swiftDocumentation` destination, rows emitted
        // by SwiftOrgStrategy. Post-#1038 SwiftBookSource owns
        // `swift-book.db` and an active `Search.SwiftBookStrategy`
        // that filters per-page emission via the shared
        // `Search.StrategyHelpers.crawlSwiftDocumentation` helper
        // with `.swiftBookOnly`.
        let provider = SwiftBookSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        #expect(provider.destinationDB == .swiftBook)
        #expect(provider.destinationDB.id == "swift-book")
        #expect(provider.destinationDB.filename == "swift-book.db")
    }

    @Test("SwiftBookSource.makeIndexer produces a Search.SwiftBookIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = SwiftBookSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.swiftBook)
        #expect(indexer.displayName == "The Swift Programming Language")
    }

    @Test("SwiftBookSource.makeStrategy returns an active SwiftBookStrategy (post-#1082; no longer a no-op)")
    func makeStrategyReturnsActiveStrategy() {
        // Pre-#1082 the strategy was effectively a no-op because the
        // resolver passed it `/dev/null` and the corpus walk found
        // nothing. Post-fix the strategy is wired to receive
        // swift-org's directory via `corpusDirectoryAlias` and emits
        // swift-book-tagged pages into swift-book.db via the shared
        // `crawlSwiftDocumentation` helper with `.swiftBookOnly`
        // scope. The source-id pin remains; the comment changes.
        let provider = SwiftBookSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        let env = Search.IndexEnvironment(
            sourceDirectory: URL(fileURLWithPath: "/tmp"),
            logger: LoggingModels.Logging.NoopRecording(),
            markdownStrategy: NoopMarkdownStrategy()
        )
        let strategy = provider.makeStrategy(env: env)
        #expect(strategy.source == Shared.Constants.SourcePrefix.swiftBook)
    }
}

// MARK: - Test fixtures

import LoggingModels

/// No-op `Search.MarkdownToStructuredPageStrategy` for IndexEnvironment fixtures.
private struct NoopMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
    func convert(markdown _: String, url _: URL?) -> Shared.Models.StructuredDocumentationPage? {
        nil
    }
}

/// Stub `Search.WebCrawlStrategyFactory` for the shape tests (#536 lift
/// 4). These tests exercise only SwiftBookSource's metadata + indexing
/// surface, not the fetch path, so the produced strategy is a no-op.
private struct StubWebCrawlStrategyFactory: Search.WebCrawlStrategyFactory {
    func makeStrategy(
        defaultCrawlBaseURL _: String,
        defaultAllowedPrefixes _: [String]?,
        candidateSessionDirectories _: [URL]
    ) -> any Search.SourceFetchStrategy {
        StubFetchStrategy()
    }
}

private struct StubFetchStrategy: Search.SourceFetchStrategy {
    func run(env _: Search.FetchEnvironment) async throws {}
}
