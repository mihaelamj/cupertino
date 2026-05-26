@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - CLI Search per-source URL resolution

//
// Pins the post-#1037/#1038 URL resolution that `openDocsFetchers`
// in `CLIImpl.Command.Search.SmartReport.swift` does before opening
// any SQLite handle. The resolution is pure (only Foundation + the
// SourceProvider registry) so it is unit-testable without a real
// `Search.Index` actor; the `openedByPath` cache in
// `openDocsFetchers` then dedups the actual file opens against the
// URLs this helper produces.
//
// Critic round 11 finding #5: the original commit (1132947) covered
// only the `augmentWithOpenTimeDegradation` merge in tests. The
// openDocsFetchers paths the commit actually changed (override-mode
// URL collapse, per-source URL mapping, unknown-id drop) were
// uncovered. This file closes that gap.
//
// Also pins `frameworkValidationSourceID` so the framework-name
// lookup in `runUnifiedSearch` stays keyed on `SourcePrefix.appleDocs`
// and doesn't silently rotate to a sibling constant (e.g. the
// `DatabaseDescriptor.id` "apple-documentation") on a future refactor.

@Suite("CLI Search per-source URL resolution")
struct CLISearchUrlResolutionTests {
    // MARK: - Test fixtures

    /// Minimal SourceProvider that returns the declared id +
    /// destinationDB; lets these tests pin the URL-resolution shape
    /// without standing up the full production registry.
    private struct StubProvider: Search.SourceProvider {
        let definition: Search.SourceDefinition
        let destinationDB: Shared.Models.DatabaseDescriptor
        let fetchInfo: Search.FetchInfo? = nil
        let capabilities: Search.Capabilities = .empty
        let legacySourceIDAliases: Set<String> = []

        func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
            preconditionFailure("URL resolution does not call makeStrategy")
        }

        func makeIndexer() -> any Search.SourceIndexer {
            preconditionFailure("URL resolution does not call makeIndexer")
        }
    }

    private static func stub(
        id: String,
        descriptor: Shared.Models.DatabaseDescriptor
    ) -> StubProvider {
        StubProvider(
            definition: .init(
                id: id,
                displayName: id,
                emoji: "📄",
                properties: Search.SourceProperties(
                    authority: 0.0,
                    freshness: 0.0,
                    comprehensiveness: 0.0,
                    codeExamples: 0.0,
                    hasAvailability: 0.0,
                    designFocus: 0.0,
                    languageFocus: 0.0,
                    searchQuality: 0.0
                ),
                intents: [],
                intentPriority: [:],
                baseURL: nil
            ),
            destinationDB: descriptor
        )
    }

    private static func productionishProviders() -> [String: any Search.SourceProvider] {
        let pairs: [(String, Shared.Models.DatabaseDescriptor)] = [
            (Shared.Constants.SourcePrefix.appleDocs, .appleDocumentation),
            (Shared.Constants.SourcePrefix.hig, .hig),
            (Shared.Constants.SourcePrefix.appleArchive, .appleArchive),
            (Shared.Constants.SourcePrefix.swiftEvolution, .swiftEvolution),
            (Shared.Constants.SourcePrefix.swiftOrg, .swiftOrg),
            (Shared.Constants.SourcePrefix.swiftBook, .swiftBook),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, stub(id: $0.0, descriptor: $0.1) as any Search.SourceProvider) })
    }

    private static let baseDir = URL(fileURLWithPath: "/tmp/cup-url-resolution")

    // MARK: - Per-source resolution (override = nil)

    @Test("Each docs source-id maps to its own per-source DB filename when no override is set")
    func perSourceResolutionWiresEachFile() {
        let urls = CLIImpl.Command.Search.urlsByDocsSourceID(
            override: nil,
            providerByID: Self.productionishProviders(),
            baseDirectory: Self.baseDir
        )
        #expect(urls[Shared.Constants.SourcePrefix.appleDocs]?.lastPathComponent
            == Shared.Models.DatabaseDescriptor.appleDocumentation.filename)
        #expect(urls[Shared.Constants.SourcePrefix.hig]?.lastPathComponent
            == Shared.Models.DatabaseDescriptor.hig.filename)
        #expect(urls[Shared.Constants.SourcePrefix.appleArchive]?.lastPathComponent
            == Shared.Models.DatabaseDescriptor.appleArchive.filename)
        #expect(urls[Shared.Constants.SourcePrefix.swiftEvolution]?.lastPathComponent
            == Shared.Models.DatabaseDescriptor.swiftEvolution.filename)
        #expect(urls[Shared.Constants.SourcePrefix.swiftOrg]?.lastPathComponent
            == Shared.Models.DatabaseDescriptor.swiftOrg.filename)
        #expect(urls[Shared.Constants.SourcePrefix.swiftBook]?.lastPathComponent
            == Shared.Models.DatabaseDescriptor.swiftBook.filename)
    }

    @Test("Per-source resolution produces 6 distinct file paths (post-#1037 invariant)")
    func perSourceResolutionProducesSixDistinctPaths() {
        let urls = CLIImpl.Command.Search.urlsByDocsSourceID(
            override: nil,
            providerByID: Self.productionishProviders(),
            baseDirectory: Self.baseDir
        )
        let distinctPaths = Set(urls.values.map(\.path))
        #expect(distinctPaths.count == 6)
        #expect(urls.count == 6)
    }

    @Test("Source-id with no registered SourceProvider is dropped from the result")
    func unknownProviderIsDropped() {
        var providers = Self.productionishProviders()
        _ = providers.removeValue(forKey: Shared.Constants.SourcePrefix.hig)
        let urls = CLIImpl.Command.Search.urlsByDocsSourceID(
            override: nil,
            providerByID: providers,
            baseDirectory: Self.baseDir
        )
        #expect(urls[Shared.Constants.SourcePrefix.hig] == nil)
        #expect(urls[Shared.Constants.SourcePrefix.appleDocs] != nil)
        #expect(urls.count == 5)
    }

    // MARK: - Override resolution

    @Test("Override URL collapses every docs source-id to the same single file (legacy --search-db back-compat)")
    func overrideCollapsesToOnePath() {
        let override = URL(fileURLWithPath: "/tmp/legacy/search.db")
        let urls = CLIImpl.Command.Search.urlsByDocsSourceID(
            override: override,
            providerByID: Self.productionishProviders(),
            baseDirectory: Self.baseDir
        )
        #expect(urls.count == 6)
        let distinctPaths = Set(urls.values.map(\.path))
        #expect(distinctPaths == [override.path])
        // Specifically: every docs source-prefix maps to the override URL.
        for prefix in [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ] {
            #expect(urls[prefix]?.path == override.path)
        }
    }

    @Test("Override wins even when the provider is missing for some source-id (override ignores the registry)")
    func overrideIgnoresRegistry() {
        let override = URL(fileURLWithPath: "/tmp/legacy/search.db")
        var providers = Self.productionishProviders()
        _ = providers.removeValue(forKey: Shared.Constants.SourcePrefix.hig)
        let urls = CLIImpl.Command.Search.urlsByDocsSourceID(
            override: override,
            providerByID: providers,
            baseDirectory: Self.baseDir
        )
        // hig got an override URL even though its provider is gone --
        // override mode doesn't gate on the registry.
        #expect(urls[Shared.Constants.SourcePrefix.hig]?.path == override.path)
        #expect(urls.count == 6)
    }

    // MARK: - Production registry round-trip

    @Test("Production registry resolves all 6 production docs sources end-to-end")
    func productionRegistryResolvesAllSix() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let providerByID: [String: any Search.SourceProvider] = Dictionary(
            uniqueKeysWithValues: registry.allEnabled.map { ($0.definition.id, $0) }
        )
        let urls = CLIImpl.Command.Search.urlsByDocsSourceID(
            override: nil,
            providerByID: providerByID,
            baseDirectory: Self.baseDir
        )
        // The 6 docs sources are all present in the production
        // registry; each maps to a distinct filename.
        #expect(urls.count == 6)
        let distinctFilenames = Set(urls.values.map(\.lastPathComponent))
        #expect(distinctFilenames.count == 6)
        // Specifically, hig must NOT collide with apple-docs etc.
        #expect(urls[Shared.Constants.SourcePrefix.hig]?.lastPathComponent
            != urls[Shared.Constants.SourcePrefix.appleDocs]?.lastPathComponent)
    }

    // MARK: - Framework-validation lookup key

    @Test("frameworkValidationSourceID stays keyed on apple-docs source-prefix")
    func frameworkValidationKeyIsAppleDocs() {
        // Pinned: runUnifiedSearch's `plan.docsIndexes[Self.frameworkValidationSourceID]`
        // must look up the apple-docs Index (framework partitioning
        // lives in apple-documentation.db). A regression that rotates
        // the constant to the DatabaseDescriptor.id "apple-documentation"
        // or any other value silently disables `--framework` validation
        // in the fan-out path; this test catches the swap.
        #expect(CLIImpl.Command.Search.frameworkValidationSourceID
            == Shared.Constants.SourcePrefix.appleDocs)
    }
}
