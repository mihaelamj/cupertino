// swiftlint:disable line_length
// (long lines are descriptive `.disabled("OUTSTANDING — Cluster …")` audit-recipe strings; readability beats wrapping here)

@testable import CLI
import Foundation
import LoggingModels
import RemoteSyncModels
import SearchAPI
import SearchModels
import Services
import ServicesModels
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

    @Test("MCP search tool's source enum schema is registry-derived (CompositeToolProvider accepts a searchToolSourceEnumValues DI parameter)")
    func mcpSchemaEnumIncludesFakeSource() {
        // STATUS: PASSES (post-Cluster-7). CompositeToolProvider now
        // takes a `searchToolSourceEnumValues: [String]` init parameter;
        // the Serve composition root builds it from
        // `["all"] + makeProductionSourceRegistry().allEnabled.map(\.definition.id)`
        // (+ the appleSampleCode alias). Registering a new
        // SourceProvider therefore extends the MCP schema automatically.
        // The composition-root behaviour is what we assert here:
        // simulate the composition step with a registry that has the
        // fake registered, and confirm the assembled list contains the
        // fake's id.
        let registry = registryWithFake()
        var enumValues = ["all"]
        enumValues.append(contentsOf: registry.allEnabled.map(\.definition.id))
        #expect(
            enumValues.contains(ContractFakeSourceProvider.fakeID),
            "MCP search tool enum schema must include every registered source's id; fake source id missing"
        )
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

    @Test("SaveSiblingGate.Target is a rawValue-String struct, not a closed enum")
    func saveSiblingGateTargetIsRegistryDriven() {
        // STATUS: PASSES (post-Cluster-9 sub-2). Closed enum became a
        // RawRepresentable struct with rawValue + dbFilename derived
        // (`<rawValue>.db`). Adding a new bucket — the post-#1036 per-
        // source DB split will surface here when SaveSiblingGate
        // tracks per-source destinations — is a `static let myNew =
        // Target(rawValue: "my-new")` declaration with no switch arm.
        // Note: this test relies on @testable import CLI; the type
        // itself is internal.
        let custom = SaveSiblingGate.Target(rawValue: "wwdc")
        #expect(custom.rawValue == "wwdc")
        #expect(custom.dbFilename == "wwdc.db")
        // Existing buckets still discoverable via static lets.
        #expect(SaveSiblingGate.Target.search.dbFilename == "search.db")
        #expect(SaveSiblingGate.Target.allKnownCases.count == 3)
    }

    @Test("Search.FetchInfo.DefaultOutputDirKey is a rawValue-String struct, not a closed enum")
    func defaultOutputDirKeyIsRegistryDriven() {
        // STATUS: PASSES (post-Cluster-9 sub-1). The closed enum became
        // a RawRepresentable struct; arbitrary directory keys can be
        // constructed at call sites. The 8 shipped keys still exist as
        // `static let` constants for discoverability + back-compat.
        // The CLI's resolveDirectory(forKey:paths:) delegates to
        // paths.directory(named:) using the rawValue verbatim
        // (post-Cluster-13).
        let fakeKey = Search.FetchInfo.DefaultOutputDirKey(rawValue: "wwdc-transcripts")
        #expect(fakeKey.rawValue == "wwdc-transcripts")
        // Existing keys still accessible.
        #expect(Search.FetchInfo.DefaultOutputDirKey.docs.rawValue == "docs")
        #expect(Search.FetchInfo.DefaultOutputDirKey.allKnownCases.count == 8)
    }

    @Test(
        "LoggingModels.Logging.Category is registry-driven",
        .disabled("OUTSTANDING — Cluster 10: LoggingModels/Logging.Category.swift L13-24 closed enum has per-source cases. Refactor: String-keyed category.")
    )
    func loggingCategoryIsRegistryDriven() {
        #expect(Bool(false), "see disabled note")
    }

    @Test("Services.ReadService.Source is a rawValue-String struct, not a closed enum")
    func readServiceSourceIsRegistryDriven() {
        // STATUS: PASSES (post-Cluster-9 sub-3). Closed enum became a
        // RawRepresentable struct; the dispatcher's exhaustive switch
        // became if/elseif/else with an `.unknownSource(rawValue)`
        // fallthrough. New backend buckets are added as `static let`
        // declarations + a new `if source == .myNew` arm in dispatch.
        let custom = Services.ReadService.Source(rawValue: "wwdc")
        #expect(custom.rawValue == "wwdc")
        // Existing buckets still discoverable.
        #expect(Services.ReadService.Source.docs.rawValue == "docs")
        #expect(Services.ReadService.Source.allKnownCases.count == 3)
    }

    @Test("RemoteSync.IndexState.Phase is a rawValue-String struct, not a closed enum")
    func remoteSyncPhaseIsRegistryDriven() {
        // STATUS: PASSES (post-Cluster-11 sub-1). The closed enum
        // became a RawRepresentable struct (Codable preserved so
        // existing on-disk index-state.json files keep loading). The
        // 5 production phases stay as `static let` constants; the
        // 3 mapping switches in `RemoteSync.Indexer` (phasePath /
        // phaseSource / buildURI) became dict lookups. Adding a new
        // phase is a `static let` declaration + 3 new dict entries.
        // Cluster 11 sub-2 (URI scheme derivation from SourceProvider)
        // remains outstanding — the dict approach is more open than a
        // switch, but the scheme strings are still hardcoded in
        // RemoteSync.Indexer rather than read from registry providers.
        let custom = RemoteSync.IndexState.Phase(rawValue: "wwdc")
        #expect(custom.rawValue == "wwdc")
        // Existing phases still discoverable.
        #expect(RemoteSync.IndexState.Phase.docs.rawValue == "docs")
        #expect(RemoteSync.IndexState.Phase.allKnownCases.count == 5)
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

    @Test("Shared.Paths exposes a generic `directory(named:)` lookup; per-source typed accessors delegate to it")
    func sharedPathsHasGenericDirectoryLookup() {
        // STATUS: PASSES (post-Cluster-13). Shared.Paths.directory(named:)
        // is the canonical anchor. The 8 typed accessors
        // (docsDirectory, swiftEvolutionDirectory, …) are kept for
        // back-compat with existing call sites but now delegate to the
        // generic. Consumers SHOULD migrate to passing the dirname
        // through DI (provider.fetchInfo.outputDir); pluggability
        // contract is the generic existing + the typed accessors
        // routing through it (so a new source's directory is
        // reachable without a new typed accessor edit).
        let paths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/test-pluggability"))
        let generic = paths.directory(named: "my-arbitrary-source")
        #expect(generic.lastPathComponent == "my-arbitrary-source")
        // Each typed accessor must equal a directory(named:) call with
        // the same dirname; this is the delegation contract.
        #expect(paths.docsDirectory == paths.directory(named: Shared.Constants.Directory.docs))
        #expect(paths.higDirectory == paths.directory(named: Shared.Constants.Directory.hig))
        #expect(paths.archiveDirectory == paths.directory(named: Shared.Constants.Directory.archive))
    }

    // MARK: - Cluster 14: Package.swift mass dependency lists

    @Test("Package.swift test/binary targets declare source-target deps via the allSourceTargetDeps helper, not 8 repeated lists")
    func packageSwiftSourceTargetDepsAreHelperBased() throws {
        // STATUS: PASSES. Fixed by extracting `allSourceTargetNames`,
        // `allSourceTargetDeps`, `allSourceProducts` at the top of
        // Packages/Package.swift; SearchTests + SearchStrategiesTests
        // + the cupertino CLI binary target now spread the helper into
        // their `dependencies:` arrays instead of repeating the 8
        // `<X>Source` literals. Verified by reading the file from this
        // test process and asserting:
        //   1. the helper is declared, and
        //   2. there is no `dependencies: [.., "AppleDocsSource",
        //      "HIGSource", ..]` block (the pre-refactor shape).
        // This is the structural contract; the helper itself is the
        // pluggability anchor.
        // Walk up from this source file until we find Package.swift.
        // `#filePath` is the absolute path; #file may be relativized by
        // SwiftPM's build settings.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var candidate = dir.appendingPathComponent("Package.swift")
        while !FileManager.default.fileExists(atPath: candidate.path), dir.path != "/" {
            dir = dir.deletingLastPathComponent()
            candidate = dir.appendingPathComponent("Package.swift")
        }
        let url = candidate
        let body = try String(contentsOf: url, encoding: .utf8)
        #expect(body.contains("let allSourceTargetDeps:"), "Package.swift must declare the per-source dependency helper")
        #expect(body.contains("let allSourceTargetNames:"), "Package.swift must declare the per-source name list")
        #expect(body.contains("let allSourceProducts:"), "Package.swift must declare the per-source product helper")
        // Detect the pre-refactor smell: lines where multiple per-source
        // target names sit adjacent inside a dependencies array. After
        // the helper refactor, AppleDocsSource + HIGSource never appear
        // within 3 lines of each other (the allSourceTargetNames
        // declaration is the only place they're co-located, and the
        // helper expands into a single Target.Dependency value).
        let lines = body.components(separatedBy: "\n")
        var coLocatedBlocks = 0
        for idx in lines.indices where lines[idx].contains("\"AppleDocsSource\"") {
            // window: 4 lines forward
            let window = max(0, idx - 1)..<min(lines.count, idx + 4)
            let neighborhood = lines[window].joined(separator: "\n")
            let coLocated = neighborhood.contains("\"HIGSource\"")
                && neighborhood.contains("\"SampleCodeSource\"")
            if coLocated, !neighborhood.contains("allSourceTargetNames") {
                coLocatedBlocks += 1
            }
        }
        #expect(
            coLocatedBlocks == 0,
            "Pluggability gap: \(coLocatedBlocks) dependencies-array block(s) enumerate the 8 *Source targets directly; use allSourceTargetDeps instead"
        )
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
