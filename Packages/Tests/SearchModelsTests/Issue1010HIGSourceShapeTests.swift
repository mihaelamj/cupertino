import Foundation
import HIGSource
import SearchModels
import SharedConstants
import Testing

// MARK: - #1010 HIGSource shape pins

/// Pins the `HIGSource: Search.SourceProvider` conformance shape
/// landed by epic #1007 Phase 1B. A regression in the static
/// `definition` / `fetchInfo` literals or the `makeIndexer` /
/// `makeStrategy` factories surfaces here before downstream
/// composition-root code path picks it up.
@Suite("#1010: HIGSource shape pins")
struct Issue1010HIGSourceShapeTests {
    @Test("HIGSource.definition carries the expected id + intents + intentPriority")
    func definitionShape() {
        let provider = HIGSource()
        let def = provider.definition
        #expect(def.id == Shared.Constants.SourcePrefix.hig)
        #expect(def.displayName == "Human Interface Guidelines")
        #expect(def.emoji == "🎨")
        #expect(def.intents == [.designGuidance])
        #expect(def.intentPriority[.designGuidance] == 100)
        #expect(def.properties.designFocus == 1.0)
        #expect(def.properties.codeExamples == 0.0)
    }

    @Test("HIGSource.fetchInfo carries the HIG crawl base + .hig output dir key")
    func fetchInfoShape() {
        let provider = HIGSource()
        let fi = try? #require(provider.fetchInfo)
        #expect(fi?.sourceID == Shared.Constants.SourcePrefix.hig)
        #expect(fi?.displayName == Shared.Constants.DisplayName.humanInterfaceGuidelines)
        #expect(fi?.crawlBaseURLs == [Shared.Constants.BaseURL.appleHIG])
        #expect(fi?.defaultOutputDirKey == .hig)
        #expect(fi?.isWebCrawlable == true)
    }

    @Test("HIGSource.makeIndexer produces a Search.HIGIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = HIGSource()
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.hig)
        #expect(indexer.displayName == "Human Interface Guidelines")
    }
}
