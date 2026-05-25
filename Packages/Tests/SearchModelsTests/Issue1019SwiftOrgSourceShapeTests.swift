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
        let provider = SwiftOrgSource()
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
        let provider = SwiftOrgSource()
        let fi = try #require(provider.fetchInfo)
        #expect(fi.sourceID == Shared.Constants.SourcePrefix.swiftOrg)
        #expect(fi.displayName == Shared.Constants.DisplayName.swiftOrgDocs)
        #expect(fi.crawlBaseURLs == [Shared.Constants.BaseURL.swiftOrg])
        #expect(fi.defaultOutputDirKey == .swiftOrg)
        #expect(fi.isWebCrawlable == true)
    }

    @Test("SwiftOrgSource.makeIndexer produces a Search.SwiftOrgIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = SwiftOrgSource()
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.swiftOrg)
        #expect(indexer.displayName == "Swift.org")
    }

    @Test("SwiftOrgSource.destinationDB == .swiftDocumentation (post step 4; host of swift-book view-source)")
    func destinationDBExplicit() {
        let provider = SwiftOrgSource()
        #expect(provider.destinationDB == .swiftDocumentation)
        #expect(provider.destinationDB.id == "swift-documentation")
    }
}
