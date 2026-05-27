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
        let searchOnlyProviders = registry.allEnabled.filter { $0.destinationDB != .packages }
        let searchOnlyIDs = Set(searchOnlyProviders.map(\.definition.id))
        #expect(!searchOnlyIDs.contains(Shared.Constants.SourcePrefix.packages))
        #expect(searchOnlyProviders.count == 7) // 8 total - 1 PackagesSource
    }

    @Test("With all input directories present, derived strategies list has 7 entries (6 real + 1 SwiftBook noop)")
    func fullInputProducesSevenStrategies() {
        let input = Self.fullInput
        let registry = CLIImpl.makeProductionSourceRegistry()
        let logger = LoggingModels.Logging.NoopRecording()
        let strategies = registry.allEnabled
            .filter { $0.destinationDB != .packages }
            .compactMap { provider -> (any Search.SourceIndexingStrategy)? in
                guard let dir = CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: provider, input: input) else {
                    return nil
                }
                let env = Search.IndexEnvironment(
                    sourceDirectory: dir,
                    logger: logger,
                    markdownStrategy: input.markdownStrategy,
                    importLogSink: nil,
                    sampleCatalogProvider: input.sampleCatalogProvider
                )
                return provider.makeStrategy(env: env)
            }
        // Pluggability invariant: with every docs-tier directory
        // present, the strategies list has one entry per docs-tier
        // provider in the registry. Adding a new docs-tier source
        // (registered + a directoryByKey entry) auto-grows the
        // count without editing this assertion.
        let expectedDocsTierProviders = registry.allEnabled
            .filter { $0.destinationDB != .packages }
            .count
        #expect(strategies.count == expectedDocsTierProviders)
    }

    @Test("With minimal input (only docsDirectory + samples), derived strategies list has 2 entries (apple-docs + samples)")
    func minimalInputSkipsOptionalDirs() {
        let input = Self.minimalInput
        let registry = CLIImpl.makeProductionSourceRegistry()
        let logger = LoggingModels.Logging.NoopRecording()
        let strategies = registry.allEnabled
            .filter { $0.destinationDB != .packages }
            .compactMap { provider -> (any Search.SourceIndexingStrategy)? in
                guard let dir = CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: provider, input: input) else {
                    return nil
                }
                let env = Search.IndexEnvironment(
                    sourceDirectory: dir,
                    logger: logger,
                    markdownStrategy: input.markdownStrategy,
                    importLogSink: nil,
                    sampleCatalogProvider: input.sampleCatalogProvider
                )
                return provider.makeStrategy(env: env)
            }
        // Pluggability invariant: with minimal input, the strategies
        // list = (providers whose dir is supplied via directoryByKey)
        // + (sentinel providers that opt out of requiresCorpusDirectory).
        // Post-#1082 swift-book is no longer a sentinel — it requires
        // the swift-org dir, which is absent here, so it drops.
        let expected = registry.allEnabled
            .filter { $0.destinationDB != .packages }
            .filter { provider in
                if let supplied = input.directoryByKey[provider.definition.id], supplied != nil {
                    return true
                }
                return !provider.requiresCorpusDirectory
            }
            .count
        #expect(strategies.count == expected)
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
        searchDBPath: URL(fileURLWithPath: "/tmp/search.db"),
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
        searchDBPath: URL(fileURLWithPath: "/tmp/search.db"),
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
