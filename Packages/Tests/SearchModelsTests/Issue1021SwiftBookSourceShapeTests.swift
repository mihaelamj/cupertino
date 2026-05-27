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

    @Test("SwiftBookSource.fetchInfo is nil — view-source has no independent fetch leg (#1082 follow-up)")
    func fetchInfoIsNil() {
        // SwiftBookSource is a view-source over swift-org's corpus.
        // `cupertino fetch --source swift-org` covers swift-book's
        // pages via shared URL-prefix crawling; a separate
        // swift-book fetch would race on swift-org's session and
        // double-fetch identical URLs. fetchInfo == nil is the
        // sentinel that excludes swift-book from
        // `allFetchableSources()` + `Doctor.checkDocumentationDirectories`.
        let provider = SwiftBookSource()
        #expect(provider.fetchInfo == nil)
    }

    @Test("SwiftBookSource.corpusDirectoryAlias == swift-org (routes resolver to swift-org's directory, #1082 follow-up)")
    func corpusDirectoryAliasIsSwiftOrg() {
        // Post-#1082 the resolver routes view-sources to the parent
        // source's directory via this property. SwiftBookSource
        // declares `swift-org` so:
        //   - `makeDocsIndexingDirectoryByKey` sets
        //     `directoryByKey["swift-book"]` to the resolved
        //     swift-org URL (inheriting any --swift-org-dir override).
        //   - `Save.Indexers` selection: `save --source swift-org`
        //     auto-includes swift-book in the group fan-out.
        let provider = SwiftBookSource()
        #expect(provider.corpusDirectoryAlias == Shared.Constants.SourcePrefix.swiftOrg)
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

    @Test("SwiftBookSource.makeStrategy returns an active SwiftBookStrategy (post-#1082; no longer a no-op)")
    func makeStrategyReturnsActiveStrategy() {
        // Pre-#1082 the strategy was effectively a no-op because the
        // resolver passed it `/dev/null` and the corpus walk found
        // nothing. Post-fix the strategy is wired to receive
        // swift-org's directory via `corpusDirectoryAlias` and emits
        // swift-book-tagged pages into swift-book.db via the shared
        // `crawlSwiftDocumentation` helper with `.swiftBookOnly`
        // scope. The source-id pin remains; the comment changes.
        let provider = SwiftBookSource()
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
