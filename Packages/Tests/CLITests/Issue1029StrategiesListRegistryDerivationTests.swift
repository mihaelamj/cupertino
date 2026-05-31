@testable import CLI
import Foundation
import LoggingModels
import SearchModels
import SharedConstants
import Testing

// MARK: - #1029 strategies-list registry-derivation pin

/// Pins the post-#1029 (Phase 1I.c.1 of epic #1007) registry-derived
/// strategies-list assembly contract. The strategies list is now
/// derived from `productionRegistry.allEnabled.filter(destinationDB
/// == .search).compactMap { provider in env-build + makeStrategy }`.
/// Pre-#1029 this was an inline 6-strategy literal with conditional
/// appends keyed on optional input fields.
@Suite("#1029: strategies list derived from registry filtered by destinationDB")
struct Issue1029StrategiesListRegistryDerivationTests {
    // MARK: - resolveSourceDirectory bridge helper

    @Test("resolveSourceDirectory returns input.docsDirectory for apple-docs source")
    func resolveAppleDocsDirectory() throws {
        let input = Self.fullInput
        let registry = CLIImpl.makeProductionSourceRegistry()
        let appleDocs = try #require(registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.appleDocs })
        #expect(CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: appleDocs, input: input) == input.docsDirectory)
    }

    @Test("resolveSourceDirectory returns nil for swift-evolution when input.evolutionDirectory is nil")
    func resolveSwiftEvolutionNilWhenInputNil() throws {
        let input = Self.minimalInput // only docsDirectory set; evolution/org/archive/hig nil
        let registry = CLIImpl.makeProductionSourceRegistry()
        let evolution = try #require(registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.swiftEvolution })
        #expect(CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: evolution, input: input) == nil)
    }

    @Test("resolveSourceDirectory returns sentinel /dev/null for samples (sourceDirectory ignored by SampleCodeStrategy)")
    func resolveSamplesIsSentinel() throws {
        let input = Self.minimalInput
        let registry = CLIImpl.makeProductionSourceRegistry()
        let samples = try #require(registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.samples })
        let resolved = CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: samples, input: input)
        #expect(resolved?.path == "/dev/null")
    }

    @Test("PackagesSource is filtered out by destinationDB != .packages (not in strategies list)")
    func packagesSourceExcludedByDestinationDB() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let allIDs = Set(registry.allEnabled.map(\.definition.id))
        let searchOnlyProviders = registry.allEnabled.filter { $0.destinationDB != .packages }
        let searchOnlyIDs = Set(searchOnlyProviders.map(\.definition.id))
        // PackagesSource is gone; every other registered source remains.
        #expect(!searchOnlyIDs.contains(Shared.Constants.SourcePrefix.packages))
        #expect(
            allIDs.contains(Shared.Constants.SourcePrefix.packages),
            "PackagesSource must be in the registry (so the filter has something to filter)"
        )
        #expect(searchOnlyIDs == allIDs.subtracting([Shared.Constants.SourcePrefix.packages]))
    }

    /// Resolves which providers' strategies survive the dispatch
    /// fan-out under a given input, expressed as the set of
    /// provider `definition.id` values. Used by the two by-id pin
    /// tests below to assert specific providers in/out of the list.
    private func dispatchedProviderIDs(input: Search.DocsIndexingInput) -> Set<String> {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let logger = LoggingModels.Logging.NoopRecording()
        var dispatched: Set<String> = []
        for provider in registry.allEnabled where provider.destinationDB != .packages {
            guard let dir = CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: provider, input: input) else {
                continue
            }
            let env = Search.IndexEnvironment(
                sourceDirectory: dir,
                logger: logger,
                markdownStrategy: input.markdownStrategy,
                importLogSink: nil,
                sampleCatalogProvider: input.sampleCatalogProvider
            )
            _ = provider.makeStrategy(env: env)
            dispatched.insert(provider.definition.id)
        }
        return dispatched
    }

    @Test("With all input directories present, every docs-tier provider's strategy appears (each named)")
    func fullInputContainsEachDocsTierStrategy() {
        // Assert each shipped docs-tier source IS present by id.
        // Hardcoded-count tests broke on new sources (pluggability
        // violation); fully-derived tests were tautological vs the
        // production resolver. Naming each source-id catches
        // regressions where a SPECIFIC provider falls out of the
        // dispatch (e.g. a future refactor breaks the swift-book
        // alias propagation and SwiftBookStrategy disappears),
        // without forcing the test to know the literal count.
        let dispatched = dispatchedProviderIDs(input: Self.fullInput)
        for expectedID in [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.samples,
        ] {
            #expect(dispatched.contains(expectedID), "\(expectedID) provider's strategy must dispatch with fullInput")
        }
    }

    @Test("With minimal input (only docsDirectory + samples), only apple-docs + samples strategies fire — each named")
    func minimalInputProducesAppleDocsAndSamples() {
        // Assert by provider source-id, not by count, so future
        // sources don't force test edits AND so we catch regressions
        // where a specific provider unexpectedly drops in/out.
        let dispatched = dispatchedProviderIDs(input: Self.minimalInput)
        // apple-docs has its dir supplied via directoryByKey →
        // appears. samples is requiresCorpusDirectory=false →
        // appears via sentinel.
        #expect(dispatched.contains(Shared.Constants.SourcePrefix.appleDocs))
        #expect(dispatched.contains(Shared.Constants.SourcePrefix.samples))
        // swift-org / swift-evolution / apple-archive / hig have NO
        // dir entry → resolver returns nil → compactMap drops them.
        for missingID in [
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
        ] {
            #expect(!dispatched.contains(missingID), "\(missingID) must NOT dispatch without its directory")
        }
        // swift-book is aliased to swift-org. With swift-org's dir
        // absent from the minimal input's directoryByKey, swift-book
        // ALSO drops out (post-#1082: view-source inherits parent's
        // entry, which is absent, so the aliased entry is also nil).
        #expect(
            !dispatched.contains(Shared.Constants.SourcePrefix.swiftBook),
            "view-source over an absent parent must drop with the parent"
        )
    }
}

// MARK: - Test fixtures

extension Issue1029StrategiesListRegistryDerivationTests {
    /// Post-#1045 Gap-4 + post-cull (2026-05-26 audit Finding 14.5):
    /// `resolveSourceDirectory` no longer reads typed fields — every
    /// per-source directory flows through `directoryByKey`. The
    /// typed `*Directory` fields remain on the Input struct for
    /// back-compat with existing callers but are not consulted by
    /// the dispatcher. Tests construct the dict directly so the
    /// assertions exercise the production code path.
    static let fullInput = Search.DocsIndexingInput(
        dbPath: URL(fileURLWithPath: "/tmp/search.db"),
        docsDirectory: URL(fileURLWithPath: "/tmp/docs"),
        evolutionDirectory: URL(fileURLWithPath: "/tmp/evo"),
        swiftOrgDirectory: URL(fileURLWithPath: "/tmp/swift-org"),
        archiveDirectory: URL(fileURLWithPath: "/tmp/archive"),
        higDirectory: URL(fileURLWithPath: "/tmp/hig"),
        clearExisting: false,
        markdownStrategy: NoopMarkdownStrategy(),
        sampleCatalogProvider: NoopSampleCatalogProvider(),
        directoryByKey: [
            Shared.Constants.SourcePrefix.appleDocs: URL(fileURLWithPath: "/tmp/docs"),
            Shared.Constants.SourcePrefix.swiftEvolution: URL(fileURLWithPath: "/tmp/evo"),
            Shared.Constants.SourcePrefix.swiftOrg: URL(fileURLWithPath: "/tmp/swift-org"),
            Shared.Constants.SourcePrefix.appleArchive: URL(fileURLWithPath: "/tmp/archive"),
            Shared.Constants.SourcePrefix.hig: URL(fileURLWithPath: "/tmp/hig"),
            // Post-#1082: swift-book's fetchInfo declares
            // defaultOutputDirKey=.swiftOrg so the dict carries the
            // SAME path as swiftOrg. The strategy then walks
            // swift-org's tree and emits only swift-book-tagged pages.
            Shared.Constants.SourcePrefix.swiftBook: URL(fileURLWithPath: "/tmp/swift-org"),
            // samples deliberately nil — dispatcher returns the
            // /dev/null sentinel (it consumes env.sampleCatalogProvider,
            // not a directory).
            Shared.Constants.SourcePrefix.samples: nil,
        ]
    )

    static let minimalInput = Search.DocsIndexingInput(
        dbPath: URL(fileURLWithPath: "/tmp/search.db"),
        docsDirectory: URL(fileURLWithPath: "/tmp/docs"),
        evolutionDirectory: nil,
        swiftOrgDirectory: nil,
        archiveDirectory: nil,
        higDirectory: nil,
        clearExisting: false,
        markdownStrategy: NoopMarkdownStrategy(),
        sampleCatalogProvider: NoopSampleCatalogProvider(),
        directoryByKey: [
            Shared.Constants.SourcePrefix.appleDocs: URL(fileURLWithPath: "/tmp/docs"),
            // Other docs sources absent from dict → resolveSourceDirectory
            // returns nil for them, makeStrategy compactMap drops them.
            // samples + swift-book sentinel via the dispatcher's
            // /dev/null fallback case.
            Shared.Constants.SourcePrefix.swiftBook: nil,
            Shared.Constants.SourcePrefix.samples: nil,
        ]
    )
}

private struct NoopMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
    func convert(markdown _: String, url _: URL?) -> Shared.Models.StructuredDocumentationPage? {
        nil
    }
}

private struct NoopSampleCatalogProvider: Search.SampleCatalogProvider {
    func fetch() async -> Search.SampleCatalogState {
        .loaded(entries: [])
    }
}
