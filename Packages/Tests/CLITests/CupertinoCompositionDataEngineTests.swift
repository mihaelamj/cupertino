@testable import CLI
@_spi(CupertinoInternal) import CupertinoComposition
import Foundation
import Testing

@Suite("CupertinoComposition data engine")
struct CupertinoCompositionDataEngineTests {
    @Test("per-source data-engine configuration uses current bundle filenames")
    func perSourceConfigurationUsesCurrentBundleFilenames() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-corpus", isDirectory: true)
        let configuration = CupertinoComposition.makePerSourceDataEngineConfiguration(corpusDirectory: base)
        let sourceFilenames = configuration.sourceCorpusResources.map(\.url.lastPathComponent)

        #expect(sourceFilenames.contains("apple-documentation.db"))
        #expect(!sourceFilenames.contains("apple-sample-code.db"))
        #expect(configuration.sampleResource?.url.lastPathComponent == "apple-sample-code.db")
        #expect(configuration.packagesResource?.url.lastPathComponent == "packages.db")
    }

    @Test("corpus helpers expose opaque bundle handles")
    func corpusHelpersExposeOpaqueBundleHandles() {
        let base = URL(fileURLWithPath: "/tmp/cupertino-corpus", isDirectory: true)

        let current = CupertinoComposition.makePerSourceDataEngineCorpus(corpusDirectory: base)
        #expect(current.directory == base)
        #expect(current.layout == .currentPerSource)
        #expect(current.schemaVersions.search > 0)
        #expect(current.schemaVersions.sample > 0)
        #expect(current.schemaVersions.packages > 0)

        let legacy = CupertinoComposition.makeLegacyDataEngineCorpus(corpusDirectory: base)
        #expect(legacy.directory == base)
        #expect(legacy.layout == .legacyThreeFile)
        #expect(legacy.schemaVersions == current.schemaVersions)
    }

    @Test("read-only data-engine composition delegates to external engine")
    func readOnlyDataEngineCompositionDelegatesToExternalEngine() async throws {
        let engine = try await CupertinoComposition.makeReadOnlyDataEngine(
            configuration: .init(sourceCorpusResources: []),
            logger: Cupertino.Context.composition.logging.recording
        )
        #expect(try await engine.documentCount() == 0)
        await engine.disconnect()
    }
}
