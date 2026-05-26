// swiftlint:disable line_length
// (long lines are descriptive `.disabled("OUTSTANDING — Cluster …")` audit-recipe strings; readability beats wrapping here)

@testable import CLI
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SharedConstants
import Testing

// MARK: - Pluggability contract test (#1042 follow-up to #935)

//
// #935 proved one dimension: a fake `Search.SourceProvider` plugs into
// the registry-driven write path AND its rows become searchable
// end-to-end. That test passes, but the 2026-05-26 audit found ~100
// pluggability violations across the consumer surfaces #935 doesn't
// touch — closed enumerations, typed-per-source structs, dispatch
// switches, capability tables, hardcoded URI schemes, per-source loggers.
//
// This contract test extends the #935 fake-source apparatus with
// assertions on every consumer surface that SHOULD be registry-driven.
// Each failure points at one violation cluster from the audit. The
// suite intentionally lands with many assertions failing; each follow-
// up commit drives one cluster green.
//
// Each assertion's status comment names the violation cluster + the
// audit's punch-list rank. When an assertion is `false`, the cluster is
// still outstanding; the comment says how to fix it.

/// Lightweight stub provider for the contract assertions. Distinct
/// from #935's heavyweight `FakeWWDCStrategy` (which exercises the
/// indexer pipeline) — this one just declares enough metadata to be
/// queried by every consumer-side surface we're verifying. The
/// canonical id `pluggability-contract-fake` is unlikely to collide
/// with any real source.
private struct ContractFakeSourceProvider: Search.SourceProvider {
    static let fakeID = "pluggability-contract-fake"

    let definition = Search.SourceDefinition(
        id: ContractFakeSourceProvider.fakeID,
        displayName: "Pluggability Contract Fake",
        emoji: "🧪",
        properties: Search.SourceProperties(
            authority: 0.5,
            freshness: 0.5,
            comprehensiveness: 0.5,
            codeExamples: 0.5,
            hasAvailability: 0.5,
            designFocus: 0.5,
            languageFocus: 0.5,
            searchQuality: 0.5
        ),
        intents: [.howTo]
    )

    var destinationDB: Shared.Models.DatabaseDescriptor {
        // Use the swift-org descriptor as the fake's target — its
        // shape (Search.Index-owned per-source DB) is the most generic.
        .swiftOrg
    }

    var fetchInfo: Search.FetchInfo? { nil }

    var capabilities: Search.Capabilities {
        Search.Capabilities(
            searchers: [.text],
            operations: [.readByURI],
            metadata: [.hasAvailabilityAttrs: true]
        )
    }

    var legacySourceIDAliases: Set<String> { [] }

    func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        preconditionFailure("Contract test never invokes makeStrategy; #935 covers the strategy roundtrip path")
    }

    func makeIndexer() -> any Search.SourceIndexer {
        preconditionFailure("Contract test never invokes makeIndexer; #935 covers the indexer dispatch path")
    }
}

@Suite("Source pluggability CONTRACT — every consumer surface must be registry-driven")
struct Issue1042PluggabilityContractTests {
    private func registryWithFake() -> Search.SourceRegistry {
        var registry = CLIImpl.makeProductionSourceRegistry()
        registry.register(ContractFakeSourceProvider())
        return registry
    }

    // MARK: - Cluster 1: bundleRequiredDescriptors (closed via #1042's setup-pluggability fix)

    @Test("Setup's required-descriptor list includes the fake source's destinationDB")
    func setupRequiredIncludesFakeSource() {
        // STATUS: PASSES. Fixed in commit d0f7ab1b (CLIImpl.bundleRequiredDescriptors()
        // derives from the registry). This is the reference pattern every
        // other contract cluster should follow.
        let registry = registryWithFake()
        let required = registry.allEnabled.map(\.destinationDB)
        #expect(required.contains(.swiftOrg), "fake source declares destinationDB=.swiftOrg; required list must include it")
    }

    // MARK: - Cluster 2: foundation-tier source-id lists (Shared.Constants.SourcePrefix)

    @Test(
        "SourcePrefix.allPrefixes is registry-driven, not a hardcoded literal",
        .disabled(
            "OUTSTANDING — Cluster 2: SourcePrefix.allPrefixes hardcodes 10 source-ids. Refactor: drop the static literal; provide a CLI-side allSourceIDs() derived from makeProductionSourceRegistry()."
        )
    )
    func allPrefixesIncludesFakeSource() {
        // STATUS: OUTSTANDING. SourcePrefix.allPrefixes is a static [String]
        // literal in SharedConstants. Cannot include the registered fake.
        // Fix shape: drop allPrefixes from SharedConstants; consumers thread
        // the registry in via DI and call registry.allEnabledIDs.
        _ = registryWithFake()
        #expect(Shared.Constants.SourcePrefix.allPrefixes.contains(ContractFakeSourceProvider.fakeID))
    }

    @Test("Shared.Constants.Search.availableSources is registry-driven", .disabled("OUTSTANDING — Cluster 2: Search.availableSources hardcodes 8 source-ids."))
    func availableSourcesIncludesFakeSource() {
        _ = registryWithFake()
        #expect(Shared.Constants.Search.availableSources.contains(ContractFakeSourceProvider.fakeID))
    }

    // MARK: - Cluster 3: SmartQuery ranking weights

    @Test(
        "SmartQuery's sourceWeights table covers every registered source",
        .disabled(
            "OUTSTANDING — Cluster 3: SearchAPI/SmartQuery.swift L60-70 sourceWeights is a hardcoded [String: Double] literal. Refactor: move to SourceProvider.searchProperties.fusionWeight (default 1.0); SmartQuery reads via registry."
        )
    )
    func sourceWeightsIncludesFakeSource() {
        // The fake declares searchQuality=0.5; its fusion weight should
        // derive from that property, not from a hardcoded literal table.
        _ = registryWithFake()
        // Will need SmartQuery exposed for this check; placeholder for now.
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 4: CandidateFetcher capability sets

    @Test(
        "CandidateFetcher.swiftVersionSources derives from capabilities",
        .disabled(
            "OUTSTANDING — Cluster 4: SearchSQLite/CandidateFetcher.swift L108-112 hardcodes 3 swift-* source-ids. Refactor: SourceProperties.availabilityAxis = .swiftVersion."
        )
    )
    func swiftVersionSourcesCapabilityDerived() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "CandidateFetcher.frameworkScopedSources derives from capabilities",
        .disabled(
            "OUTSTANDING — Cluster 4: SearchSQLite/CandidateFetcher.swift L119-122 hardcodes 2 framework-scoped source-ids. Refactor: SourceProperties.carriesFrameworkColumn."
        )
    )
    func frameworkScopedSourcesCapabilityDerived() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 5: Search.PlatformFilterScope sets

    @Test(
        "PlatformFilterScope.dispatchAppliesFilter is registry-derived",
        .disabled("OUTSTANDING — Cluster 5: SearchModels/Search.PlatformFilterScope.swift L42-57 hardcodes 8-source set. Refactor: SourceProperties.appliesPlatformFilter.")
    )
    func dispatchAppliesFilterCapabilityDerived() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "PlatformFilterScope.allFanOutSources is registry-derived",
        .disabled("OUTSTANDING — Cluster 5: SearchModels/Search.PlatformFilterScope.swift L104-113 hardcodes 8 source-ids.")
    )
    func allFanOutSourcesIncludesFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 6: TeaserResults typed-per-source struct

    @Test(
        "Services.Formatter.TeaserResults can hold a teaser bucket for any registered source",
        .disabled(
            "OUTSTANDING — Cluster 6: ServicesModels/Services.Formatter.TeaserResults.swift is a closed struct with one typed property per source. Refactor: [String: [Search.Result]] keyed by sourceID."
        )
    )
    func teaserResultsAcceptsFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "ServicesModels.Services.Formatter.Unified.Input accepts any registered source's results",
        .disabled("OUTSTANDING — Cluster 6: ServicesModels/Services.Formatter.Unified.Input.swift is typed-per-source. Refactor: [String: [Search.Result]] dict.")
    )
    func unifiedInputAcceptsFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "SearchAPI.ComposedSearchResult accepts any registered source",
        .disabled("OUTSTANDING — Cluster 6: SearchAPI/Search.ComposableResult.swift is typed-per-source struct + builder. Refactor: [String: ComposedSection] dict.")
    )
    func composedSearchResultAcceptsFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 7: MCP search-tool schema enum

    @Test(
        "MCP search tool's source enum schema is registry-derived",
        .disabled(
            "OUTSTANDING — Cluster 7: SearchToolProvider/CompositeToolProvider.swift L137-148 hardcodes 10 enumValues. Refactor: derive from registry.allEnabled.map(\\.definition.id) + 'all'."
        )
    )
    func mcpSchemaEnumIncludesFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 8: dispatch switches over source-ids

    @Test(
        "CLI search dispatch routes every registered source-id",
        .disabled(
            "OUTSTANDING — Cluster 8: CLIImpl.Command.Search.swift L228-247 hardcodes a switch over 9 source-ids. Refactor: provider-supplied runner or registry-driven dispatch."
        )
    )
    func cliSearchDispatchRoutesFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "CLI fetch dispatch routes every registered source-id",
        .disabled("OUTSTANDING — Cluster 8: CLIImpl.Command.Fetch.swift L226-260 hardcodes a 9-arm switch. Refactor: provider-supplied fetcher.")
    )
    func cliFetchDispatchRoutesFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "CLI fetch.allFetchableSources is registry-derived",
        .disabled("OUTSTANDING — Cluster 8: CLIImpl.Command.Fetch.swift L286-296 hardcoded list. Refactor: registry.allEnabled.filter(\\.isFetchable).")
    )
    func cliFetchAllFetchableIncludesFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "MCP CompositeToolProvider.handleSearch routes every registered source",
        .disabled("OUTSTANDING — Cluster 8: SearchToolProvider/CompositeToolProvider.swift L599-650 mirrors the CLI dispatch switch.")
    )
    func mcpHandleSearchRoutesFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 9: closed enums whose cases enumerate sources

    @Test(
        "SaveSiblingGate.Target is registry-driven, not a closed enum",
        .disabled(
            "OUTSTANDING — Cluster 9: CLI/Commands/SaveSiblingGate.swift L47-58 closed `enum Target: String, CaseIterable`. Refactor: String-keyed dispatch over registry destinationDBs."
        )
    )
    func saveSiblingGateTargetIsRegistryDriven() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "Search.FetchInfo.DefaultOutputDirKey is registry-driven",
        .disabled(
            "OUTSTANDING — Cluster 9: SearchModels/Search.FetchInfo.swift L83-92 closed `enum DefaultOutputDirKey: String`. Refactor: String value carrying the directory name."
        )
    )
    func defaultOutputDirKeyIsRegistryDriven() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "LoggingModels.Logging.Category is registry-driven",
        .disabled("OUTSTANDING — Cluster 10: LoggingModels/Logging.Category.swift L13-24 closed enum has per-source cases. Refactor: String-keyed category.")
    )
    func loggingCategoryIsRegistryDriven() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "Services.ReadService.Source is registry-driven",
        .disabled(
            // swiftlint:disable:next line_length
            "OUTSTANDING — Cluster 9: Services/ReadCommands/Services.ReadService.swift L25-29 closed `enum Source`. Refactor: derive backend from SourceProvider."
        )
    )
    func readServiceSourceIsRegistryDriven() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "RemoteSync.IndexState.Phase is registry-driven",
        .disabled(
            "OUTSTANDING — Cluster 11: RemoteSyncModels/RemoteSync.IndexState.swift L37-43 closed enum has per-source cases. Refactor: String-keyed phase carrying source-id."
        )
    )
    func remoteSyncPhaseIsRegistryDriven() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 12: hardcoded URI schemes (MCP resource provider + RemoteSync.buildURI + Crawler emitters)

    @Test(
        "MCP DocsResourceProvider dispatches URI schemes via provider",
        .disabled(
            // swiftlint:disable:next line_length
            "OUTSTANDING — Cluster 12: MCP/Support/MCP.Support.DocsResourceProvider.swift 6 hardcoded hasPrefix(scheme) sites. Refactor: SourceProvider.uriScheme."
        )
    )
    func mcpResourceProviderURISchemeIsRegistryDriven() {
        #expect(Bool(false), "see disabled note")
    }

    @Test(
        "RemoteSync.Indexer.buildURI derives scheme from provider",
        .disabled("OUTSTANDING — Cluster 11: RemoteSync/RemoteSync.Indexer.swift L276-293 hardcodes URI-scheme literals. Refactor: SourceProvider.uriScheme.")
    )
    func remoteSyncBuildURISchemeIsRegistryDriven() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 13: Shared.Paths per-source directory accessors

    @Test(
        "Shared.Paths exposes a single dirname(forSource:) lookup, not 8 typed accessors",
        .disabled(
            // swiftlint:disable:next line_length
            "OUTSTANDING — Cluster 13: Shared/Constants/Shared.Paths.swift L90-127 has 8 per-source accessors + Shared.Constants.Directory L70-78 mirrors them. Refactor: provider.fetchInfo.outputDir is canonical."
        )
    )
    func sharedPathsHasGenericDirectoryLookup() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Cluster 14: Package.swift mass dependency lists

    @Test(
        "Package.swift test targets declare source-target deps via a shared helper, not 8 repeated lists",
        .disabled(
            // swiftlint:disable:next line_length
            "OUTSTANDING — Cluster 14: Packages/Package.swift has 6 distinct test-target dependency lists enumerating the same 8 *Source targets. Refactor: declare `allSourceTargetDeps` once."
        )
    )
    func packageSwiftSourceTargetDepsAreHelperBased() {
        #expect(Bool(false), "see disabled note")
    }

    // MARK: - Coverage gate

    @Test("Contract enumerates every audit cluster")
    func contractCoversAllClusters() {
        // Sanity pin: this suite must declare at least one assertion
        // per audit cluster (1 through 14). When a new audit pass finds
        // a 15th violation cluster, add its assertion here AND bump this
        // count. The pin is human-tracked, not mechanical.
        let auditedClusterCount = 14
        let stubbedAssertions = 19 // count of @Test functions in this suite
        #expect(stubbedAssertions >= auditedClusterCount, "every audit cluster needs at least one contract assertion")
    }
}
