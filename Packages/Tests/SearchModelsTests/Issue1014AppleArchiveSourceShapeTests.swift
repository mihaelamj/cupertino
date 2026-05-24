import AppleArchiveSource
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #1014 AppleArchiveSource shape pins + destinationDB protocol pin

/// Pins the `AppleArchiveSource: Search.SourceProvider` conformance
/// shape landed by epic #1007 Phase 1D. Also pins the protocol-level
/// `destinationDB` declaration introduced in this PR (every
/// SourceProvider conformer must declare a non-default
/// `Shared.Models.DatabaseDescriptor`; no implicit search.db
/// routing).
@Suite("#1014: AppleArchiveSource shape pins + destinationDB pins")
struct Issue1014AppleArchiveSourceShapeTests {
    @Test("AppleArchiveSource.definition carries the expected id + intents + intentPriority")
    func definitionShape() {
        let provider = AppleArchiveSource()
        let def = provider.definition
        #expect(def.id == Shared.Constants.SourcePrefix.appleArchive)
        #expect(def.displayName == "Apple Archive (Legacy)")
        #expect(def.emoji == "📚")
        #expect(def.intents == [.legacy, .migration, .troubleshooting])
        #expect(def.intentPriority[.legacy] == 100)
        #expect(def.properties.freshness == 0.3) // archive is legacy
        #expect(def.properties.codeExamples == 0.6)
    }

    @Test("AppleArchiveSource.fetchInfo carries the archive crawl base + .archive output dir key + isWebCrawlable false")
    func fetchInfoShape() throws {
        let provider = AppleArchiveSource()
        let fi = try #require(provider.fetchInfo)
        #expect(fi.sourceID == Shared.Constants.SourcePrefix.appleArchive)
        #expect(fi.displayName == Shared.Constants.DisplayName.archive)
        #expect(fi.crawlBaseURLs == [Shared.Constants.BaseURL.appleArchive])
        #expect(fi.defaultOutputDirKey == .archive)
        #expect(fi.isWebCrawlable == false) // archive isn't a web crawl per FetchType.webCrawlTypes
    }

    @Test("AppleArchiveSource.makeIndexer produces a Search.AppleArchiveIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = AppleArchiveSource()
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.appleArchive)
        #expect(indexer.displayName == "Apple Archive")
    }

    @Test("AppleArchiveSource.destinationDB declares .search (no implicit routing)")
    func destinationDBExplicit() {
        let provider = AppleArchiveSource()
        #expect(provider.destinationDB == .search)
        #expect(provider.destinationDB.id == "search")
    }
}
