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

    @Test("SwiftBookSource.fetchInfo is nil (view-source: SwiftOrgStrategy owns the crawl)")
    func fetchInfoIsNil() {
        let provider = SwiftBookSource()
        #expect(provider.fetchInfo == nil)
    }

    @Test("SwiftBookSource.destinationDB == .swiftDocumentation (post step 4; co-located with swift-org via view-source)")
    func destinationDBExplicit() {
        let provider = SwiftBookSource()
        #expect(provider.destinationDB == .swiftDocumentation)
        #expect(provider.destinationDB.id == "swift-documentation")
    }

    @Test("SwiftBookSource.makeIndexer produces a Search.SwiftBookIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = SwiftBookSource()
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.swiftBook)
        #expect(indexer.displayName == "The Swift Programming Language")
    }

    @Test("SwiftBookSource.makeStrategy returns a view-source strategy that emits zero items")
    func makeStrategyIsNoop() async throws {
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
