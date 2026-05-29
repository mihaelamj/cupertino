import Foundation
import LoggingModels
import PackagesSource
import SearchModels
import SharedConstants
import Testing

// MARK: - #1023 PackagesSource shape pins (first non-.search destinationDB)

@Suite("#1023: PackagesSource shape pins (first .packages destinationDB)")
struct Issue1023PackagesSourceShapeTests {
    @Test("PackagesSource.definition carries the packages id + packageDiscovery intent")
    func definitionShape() {
        let provider = PackagesSource(packageFetchStrategyFactory: StubPackageFetchStrategyFactory())
        let def = provider.definition
        #expect(def.id == Shared.Constants.SourcePrefix.packages)
        #expect(def.displayName == "Swift Packages")
        #expect(def.emoji == "📦")
        #expect(def.intents == [.packageDiscovery])
        #expect(def.intentPriority[.packageDiscovery] == 100)
        #expect(def.properties.authority == 0.6)
    }

    @Test("PackagesSource.fetchInfo carries the swift-package-index source + .packages output dir + isWebCrawlable false")
    func fetchInfoShape() throws {
        let provider = PackagesSource(packageFetchStrategyFactory: StubPackageFetchStrategyFactory())
        let fi = try #require(provider.fetchInfo)
        #expect(fi.sourceID == Shared.Constants.SourcePrefix.packages)
        #expect(fi.displayName == Shared.Constants.DisplayName.swiftPackages)
        #expect(fi.crawlBaseURLs.isEmpty) // API-based + GitHub archive download, not URL crawl
        #expect(fi.defaultOutputDirKey == .packages)
        #expect(fi.isWebCrawlable == false)
    }

    @Test("PackagesSource.destinationDB == .packages (the load-bearing protocol-contract pin)")
    func destinationDBIsPackages() {
        let provider = PackagesSource(packageFetchStrategyFactory: StubPackageFetchStrategyFactory())
        #expect(provider.destinationDB == .packages)
        #expect(provider.destinationDB.id == "packages")
        // PackagesSource targets the non-search-style .packages descriptor.
        // Post step 4 of per-source-db-split.md, only SampleCodeSource is still at .search.
        #expect(provider.destinationDB != .search)
    }

    @Test("PackagesSource.makeIndexer returns a no-op indexer advertising source-id packages")
    func makeIndexerNoop() {
        let provider = PackagesSource(packageFetchStrategyFactory: StubPackageFetchStrategyFactory())
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.packages)
        #expect(indexer.displayName == "Swift Packages")
    }

    @Test("PackagesSource.makeStrategy returns a view-source strategy advertising source-id packages")
    func makeStrategyNoop() {
        let provider = PackagesSource(packageFetchStrategyFactory: StubPackageFetchStrategyFactory())
        let env = Search.IndexEnvironment(
            sourceDirectory: URL(fileURLWithPath: "/tmp"),
            logger: LoggingModels.Logging.NoopRecording(),
            markdownStrategy: NoopMarkdownStrategy()
        )
        let strategy = provider.makeStrategy(env: env)
        #expect(strategy.source == Shared.Constants.SourcePrefix.packages)
    }
}

// MARK: - Test fixtures

/// No-op `Search.MarkdownToStructuredPageStrategy` for IndexEnvironment fixtures.
private struct NoopMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
    func convert(markdown _: String, url _: URL?) -> Shared.Models.StructuredDocumentationPage? {
        nil
    }
}

/// Stub `Search.PackageFetchStrategyFactory` for the shape tests (#536
/// lift 5). These tests exercise only PackagesSource's metadata surface,
/// not the fetch path, so the produced strategy is a no-op and never run.
private struct StubPackageFetchStrategyFactory: Search.PackageFetchStrategyFactory {
    func makeStrategy() -> any Search.SourceFetchStrategy {
        StubFetchStrategy()
    }
}

private struct StubFetchStrategy: Search.SourceFetchStrategy {
    func run(env _: Search.FetchEnvironment) async throws {}
}
