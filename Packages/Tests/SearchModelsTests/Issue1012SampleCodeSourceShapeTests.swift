import Foundation
import LoggingModels
import SampleCodeSource
import SearchModels
import SharedConstants
import Testing

// MARK: - #1012 SampleCodeSource shape pins

/// Pins the `SampleCodeSource: Search.SourceProvider` conformance
/// shape landed by epic #1007 Phase 1C. First per-source target to
/// require a runtime dep (`env.sampleCatalogProvider`) beyond the
/// shared `IndexEnvironment` fields; the precondition behavior is
/// documented by the comment on `makeStrategy` in
/// `SampleCodeSource.swift` and verified at the type level by the
/// `indexEnvironmentExposesOptionalSampleCatalogProvider` test
/// below.
@Suite("#1012: SampleCodeSource shape pins")
struct Issue1012SampleCodeSourceShapeTests {
    @Test("SampleCodeSource.definition carries the expected id + intents + intentPriority")
    func definitionShape() {
        let provider = SampleCodeSource()
        let def = provider.definition
        #expect(def.id == Shared.Constants.SourcePrefix.samples)
        #expect(def.displayName == "Sample Code")
        #expect(def.emoji == "💻")
        #expect(def.intents == [.howTo, .troubleshooting, .conceptual])
        #expect(def.intentPriority[.howTo] == 100)
        #expect(def.properties.codeExamples == 1.0)
        #expect(def.properties.designFocus == 0.4)
    }

    @Test("SampleCodeSource.fetchInfo carries the GitHub-clone shape (no crawl base, isWebCrawlable false)")
    func fetchInfoShape() throws {
        let provider = SampleCodeSource()
        let fi = try #require(provider.fetchInfo)
        #expect(fi.sourceID == Shared.Constants.SourcePrefix.samples)
        #expect(fi.displayName == "Sample Code (GitHub)")
        #expect(fi.crawlBaseURLs.isEmpty)
        #expect(fi.defaultOutputDirKey == .sampleCode)
        #expect(fi.isWebCrawlable == false)
    }

    @Test("SampleCodeSource.makeIndexer produces a Search.SampleCodeIndexer carrying the expected sourceID")
    func makeIndexerShape() {
        let provider = SampleCodeSource()
        let indexer = provider.makeIndexer()
        #expect(indexer.sourceID == Shared.Constants.SourcePrefix.samples)
        #expect(indexer.displayName == "Sample Code")
    }

    @Test("Search.IndexEnvironment exposes sampleCatalogProvider as optional, defaulting to nil")
    func indexEnvironmentExposesOptionalSampleCatalogProvider() {
        // Confirms the #1012 IndexEnvironment extension: AppleDocs / HIG
        // callsites that don't supply sampleCatalogProvider keep their
        // existing construction shape (default nil).
        let env = Search.IndexEnvironment(
            sourceDirectory: URL(fileURLWithPath: "/tmp"),
            logger: LoggingModels.Logging.NoopRecording(),
            markdownStrategy: NoopMarkdownStrategy()
        )
        #expect(env.sampleCatalogProvider == nil)
    }
}

// MARK: - Test fixtures

/// No-op `Search.MarkdownToStructuredPageStrategy` for
/// IndexEnvironment fixtures. Tests don't exercise the markdown
/// conversion path; this conformer returns nil for any input.
/// (Logger is supplied by the canonical `LoggingModels.Logging.NoopRecording`;
/// no markdown-strategy noop ships in SearchModels yet — kept local.)
private struct NoopMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
    func convert(markdown _: String, url _: URL?) -> Shared.Models.StructuredDocumentationPage? {
        nil
    }
}
