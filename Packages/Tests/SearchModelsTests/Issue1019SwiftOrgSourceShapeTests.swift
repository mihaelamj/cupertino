import Foundation
import SearchModels
import SharedConstants
import SwiftOrgSource
import Testing

// MARK: - #1019 SwiftOrgSource shape pins

@Suite("#1019: SwiftOrgSource shape pins")
struct Issue1019SwiftOrgSourceShapeTests {
    @Test("SwiftOrgSource.definition carries the expected id + intents + intentPriority")
    func definitionShape() {
        let provider = SwiftOrgSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        let def = provider.definition
        #expect(def.id == Shared.Constants.SourcePrefix.swiftOrg)
        #expect(def.displayName == "Swift.org")
        #expect(def.emoji == "🦅")
        #expect(def.intents == [.languageFeature, .conceptual, .howTo])
        #expect(def.intentPriority[.languageFeature] == 80)
        #expect(def.properties.languageFocus == 0.8)
    }

    @Test("SwiftOrgSource.fetchInfo carries the swift.org crawl base + .swiftOrg dir key + isWebCrawlable true")
    func fetchInfoShape() throws {
        let provider = SwiftOrgSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        let fi = try #require(provider.fetchInfo)
        #expect(fi.sourceID == Shared.Constants.SourcePrefix.swiftOrg)
        #expect(fi.displayName == Shared.Constants.DisplayName.swiftOrgDocs)
        #expect(fi.crawlBaseURLs == [Shared.Constants.BaseURL.swiftOrg])
        #expect(fi.defaultOutputDirKey == .swiftOrg)
        #expect(fi.isWebCrawlable == true)
    }

    @Test("SwiftOrgSource.makeIndexer produces a Search.SwiftOrgIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = SwiftOrgSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.swiftOrg)
        #expect(indexer.displayName == "Swift.org")
    }

    @Test("SwiftOrgSource.destinationDB == .swiftOrg (post #1038 'diff db for each source'; swift-org owns swift-org.db)")
    func destinationDBExplicit() {
        // Pre-#1038 SwiftOrgSource was the view-source host for
        // swift-book and wrote to `.swiftDocumentation`
        // (`swift-documentation.db`). Post-#1038 each sub-source owns
        // its own DB; SwiftOrgSource writes to `swift-org.db` via its
        // strategy's `.swiftOrgOnly` scope filter on the shared
        // `Search.StrategyHelpers.crawlSwiftDocumentation` helper.
        let provider = SwiftOrgSource(webCrawlStrategyFactory: StubWebCrawlStrategyFactory())
        #expect(provider.destinationDB == .swiftOrg)
        #expect(provider.destinationDB.id == "swift-org")
        #expect(provider.destinationDB.filename == "swift-org.db")
    }
}

// MARK: - Test fixtures

/// Stub `Search.WebCrawlStrategyFactory` for the shape tests (#536 lift
/// 4). These tests exercise only SwiftOrgSource's metadata surface, not
/// the fetch path, so the produced strategy is a no-op and never run.
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
