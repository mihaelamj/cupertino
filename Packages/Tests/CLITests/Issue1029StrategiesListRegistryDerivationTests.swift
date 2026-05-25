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
    func resolveAppleDocsDirectory() {
        let input = Self.fullInput
        let registry = CLIImpl.makeProductionSourceRegistry()
        let appleDocs = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.appleDocs }!
        #expect(CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: appleDocs, input: input) == input.docsDirectory)
    }

    @Test("resolveSourceDirectory returns nil for swift-evolution when input.evolutionDirectory is nil")
    func resolveSwiftEvolutionNilWhenInputNil() {
        let input = Self.minimalInput // only docsDirectory set; evolution/org/archive/hig nil
        let registry = CLIImpl.makeProductionSourceRegistry()
        let evolution = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.swiftEvolution }!
        #expect(CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: evolution, input: input) == nil)
    }

    @Test("resolveSourceDirectory returns sentinel /dev/null for samples (sourceDirectory ignored by SampleCodeStrategy)")
    func resolveSamplesIsSentinel() {
        let input = Self.minimalInput
        let registry = CLIImpl.makeProductionSourceRegistry()
        let samples = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.samples }!
        let resolved = CLIImpl.Command.Save.LiveDocsIndexingRunner.resolveSourceDirectory(for: samples, input: input)
        #expect(resolved?.path == "/dev/null")
    }

    @Test("PackagesSource is filtered out by destinationDB == .search (not in strategies list)")
    func packagesSourceExcludedByDestinationDB() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let searchOnlyProviders = registry.allEnabled.filter { $0.destinationDB == .search }
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
            .filter { $0.destinationDB == .search }
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
        #expect(strategies.count == 7) // apple-docs + hig + samples + apple-archive + swift-evolution + swift-org + swift-book (noop)
    }

    @Test("With minimal input (only docsDirectory + samples), derived strategies list has 3 entries (apple-docs + samples + swift-book noop)")
    func minimalInputSkipsOptionalDirs() {
        let input = Self.minimalInput
        let registry = CLIImpl.makeProductionSourceRegistry()
        let logger = LoggingModels.Logging.NoopRecording()
        let strategies = registry.allEnabled
            .filter { $0.destinationDB == .search }
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
        // apple-docs (docsDir) + samples (sentinel) + swift-book (sentinel fallback) = 3.
        // swift-evolution / swift-org / apple-archive / hig skipped (nil dirs).
        #expect(strategies.count == 3)
    }
}

// MARK: - Test fixtures

extension Issue1029StrategiesListRegistryDerivationTests {
    static let fullInput = Search.DocsIndexingInput(
        searchDBPath: URL(fileURLWithPath: "/tmp/search.db"),
        docsDirectory: URL(fileURLWithPath: "/tmp/docs"),
        evolutionDirectory: URL(fileURLWithPath: "/tmp/evo"),
        swiftOrgDirectory: URL(fileURLWithPath: "/tmp/swift-org"),
        archiveDirectory: URL(fileURLWithPath: "/tmp/archive"),
        higDirectory: URL(fileURLWithPath: "/tmp/hig"),
        clearExisting: false,
        markdownStrategy: NoopMarkdownStrategy(),
        sampleCatalogProvider: NoopSampleCatalogProvider()
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
        sampleCatalogProvider: NoopSampleCatalogProvider()
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
