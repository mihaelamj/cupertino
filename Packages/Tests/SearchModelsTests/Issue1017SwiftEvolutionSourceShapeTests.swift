import Foundation
import SearchModels
import SharedConstants
import SwiftEvolutionSource
import Testing

// MARK: - #1017 SwiftEvolutionSource shape pins

@Suite("#1017: SwiftEvolutionSource shape pins")
struct Issue1017SwiftEvolutionSourceShapeTests {
    @Test("SwiftEvolutionSource.definition carries the expected id + intents + intentPriority")
    func definitionShape() {
        let provider = SwiftEvolutionSource()
        let def = provider.definition
        #expect(def.id == Shared.Constants.SourcePrefix.swiftEvolution)
        #expect(def.displayName == "Swift Evolution")
        #expect(def.emoji == "🔮")
        #expect(def.intents == [.languageFeature, .migration, .conceptual])
        #expect(def.intentPriority[.languageFeature] == 100)
        #expect(def.properties.languageFocus == 1.0)
        #expect(def.properties.freshness == 0.95)
    }

    @Test("SwiftEvolutionSource.fetchInfo carries the swift.org/swift-evolution crawl base + .swiftEvolution dir key")
    func fetchInfoShape() throws {
        let provider = SwiftEvolutionSource()
        let fi = try #require(provider.fetchInfo)
        #expect(fi.sourceID == Shared.Constants.SourcePrefix.swiftEvolution)
        #expect(fi.displayName == Shared.Constants.DisplayName.swiftEvolution)
        #expect(fi.crawlBaseURLs == [Shared.Constants.BaseURL.swiftEvolution])
        #expect(fi.defaultOutputDirKey == .swiftEvolution)
        #expect(fi.isWebCrawlable == true) // evolution IS in webCrawlTypes
    }

    @Test("SwiftEvolutionSource.makeIndexer produces a Search.SwiftEvolutionIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = SwiftEvolutionSource()
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.swiftEvolution)
        #expect(indexer.displayName == "Swift Evolution")
    }

    @Test("SwiftEvolutionSource.destinationDB == .swiftEvolution (post step 4 of per-source-db-split.md)")
    func destinationDBExplicit() {
        let provider = SwiftEvolutionSource()
        #expect(provider.destinationDB == .swiftEvolution)
        #expect(provider.destinationDB.id == "swift-evolution")
    }
}
