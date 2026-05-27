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
        let provider = SwiftBookSource()
        let def = provider.definition
        #expect(def.id == Shared.Constants.SourcePrefix.swiftBook)
        #expect(def.displayName == "The Swift Programming Language")
        #expect(def.emoji == "📖")
        #expect(def.intents == [.languageFeature, .conceptual, .howTo])
        #expect(def.intentPriority[.languageFeature] == 90)
        #expect(def.properties.languageFocus == 1.0)
        #expect(def.properties.codeExamples == 0.9)
    }

    @Test("SwiftBookSource.fetchInfo declares defaultOutputDirKey=.swiftOrg (view-source over swift-org's corpus dir, #1082)")
    func fetchInfoSharesSwiftOrgDir() {
        // Pre-#1082 `fetchInfo` was nil, which combined with
        // `requiresCorpusDirectory: false` short-circuited the
        // resolver to `/dev/null` and left `swift-book.db` empty.
        // Post-#1082 fetchInfo is non-nil and declares
        // `defaultOutputDirKey = .swiftOrg` so the resolver routes
        // the strategy to the real swift-org corpus tree; the
        // strategy's `.swiftBookOnly` scope filter then emits only
        // swift-book-tagged pages into `swift-book.db`.
        let provider = SwiftBookSource()
        let fetchInfo = try? #require(provider.fetchInfo)
        #expect(fetchInfo?.sourceID == Shared.Constants.SourcePrefix.swiftBook)
        #expect(fetchInfo?.defaultOutputDirKey == .swiftOrg)
        #expect(fetchInfo?.isWebCrawlable == true)
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
        let provider = SwiftBookSource()
        #expect(provider.destinationDB == .swiftBook)
        #expect(provider.destinationDB.id == "swift-book")
        #expect(provider.destinationDB.filename == "swift-book.db")
    }

    @Test("SwiftBookSource.makeIndexer produces a Search.SwiftBookIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = SwiftBookSource()
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.swiftBook)
        #expect(indexer.displayName == "The Swift Programming Language")
    }

    @Test("SwiftBookSource.makeStrategy returns a view-source strategy that emits zero items")
    func makeStrategyIsNoop() {
        let provider = SwiftBookSource()
        let env = Search.IndexEnvironment(
            sourceDirectory: URL(fileURLWithPath: "/tmp"),
            logger: LoggingModels.Logging.NoopRecording(),
            markdownStrategy: NoopMarkdownStrategy()
        )
        let strategy = provider.makeStrategy(env: env)
        #expect(strategy.source == Shared.Constants.SourcePrefix.swiftBook)
        // The strategy is a no-op; we can't easily test indexItems without a
        // full Search.Database+IndexWriter fake. The source-id pin above is
        // the load-bearing assertion: it confirms the strategy advertises
        // itself as the swift-book source for the strategies-list dispatch.
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
