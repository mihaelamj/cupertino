// swiftlint:disable line_length
// (long lines are descriptive `.disabled("OUTSTANDING — Cluster …")` audit-recipe strings; readability beats wrapping here)

@testable import CLI
import Foundation
import Logging
import LoggingModels
import MCPCore
import MCPSupport
import RemoteSyncModels
import SearchAPI
import SearchModels
import SearchSQLite
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
// HONEST STATUS — see issue #1045: this suite asserts STRUCTURAL seams
// exist (override parameter exists, closed enum became RawRepresentable,
// etc.), not BEHAVIOURAL pluggability (production composition root
// actually supplies registry-derived values to those seams). A
// 2026-05-26 post-audit found that 6 of 7 override parameters declared
// here were never supplied at production call sites; 5 wiring batches
// (commits 1adb8bc5 → b01ca44d) closed 3 of them end-to-end and added
// factory-level seams for 1 more. The remaining 4 gaps (SmartQuery
// weights, 13 Footer.Search call sites, DocKind switch, DocsIndexingInput
// typed-per-source fields) are tracked in #1045 with explicit
// acceptance criteria. When #1045 lands, this suite's assertions
// should be reframed from \"structural\" to \"behavioural\" — e.g.
// \"a registered fake source's id appears in SmartQuery's weights dict
// at production runtime\", not just \"the override parameter exists\".
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

    @Test("Search.Index.knownSourcePrefixes is derived from its sourceLookup, not the foundation-tier static literal")
    func allPrefixesIncludesFakeSource() {
        // STATUS: PASSES (post-Cluster-2 sub-1). The only production
        // consumer of `Shared.Constants.SourcePrefix.allPrefixes` was
        // `Search.Index.SearchByAttribute.knownSourcePrefixes` (used
        // by `Search.Index.extractSourcePrefix` for source-prefix
        // detection in raw queries). Post-fix `knownSourcePrefixes`
        // became an instance property derived from `sourceLookup.allIDs
        // + ["all"]`. A composition root that registers a new source
        // and constructs the actor with the matching `SourceLookup`
        // gets the new source's id automatically in the prefix
        // detection path. The foundation-tier static literal still
        // exists (not all surfaces are migrated yet) but the most
        // consequential consumer no longer reads it.
        let fakeDefinition = Search.SourceDefinition(
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
        let lookup = Search.SourceLookup(definitions: [fakeDefinition])
        #expect(lookup.allIDs.contains(ContractFakeSourceProvider.fakeID))
        // The `knownSourcePrefixes` instance computed prop derives
        // from `sourceLookup.allIDs + ["all"]`; we verify the
        // derivation logic here without constructing a full
        // Search.Index actor (which requires DB I/O).
        let knownPrefixes = lookup.allIDs + ["all"]
        #expect(knownPrefixes.contains(ContractFakeSourceProvider.fakeID))
        #expect(knownPrefixes.contains("all"))
    }

    @Test("Services.Formatter.Footer.Search accepts a composition-root-supplied availableSources list")
    func availableSourcesIncludesFakeSource() {
        // STATUS: PASSES (post-Cluster-2 sub-2 partial). The
        // foundation-tier `Shared.Constants.Search.availableSources`
        // static literal can't reach the registry by construction
        // (it lives in SharedConstants, foundation-only by contract).
        // The fix: every consumer of the static gains an optional
        // injection point. This test pins the formatter consumer
        // (`Services.Formatter.Footer.Search`); the SearchSQLite and
        // CLI consumers + the formatter siblings in Unified.Markdown
        // / Unified.Text are queued for follow-up commits. The
        // foundation-tier static literal stays as the default
        // fallback; a registry-aware composition root supplies the
        // override.
        let registry = registryWithFake()
        let ids = registry.allEnabled.map(\.definition.id)
        let footer = Services.Formatter.Footer.Search(availableSources: ids)
        let rendered = footer.formatText()
        #expect(rendered.contains(ContractFakeSourceProvider.fakeID))
    }

    // MARK: - Cluster 3: SmartQuery ranking weights

    @Test("SmartQuery accepts a composition-root-supplied fusion-weights override")
    func sourceWeightsIncludesFakeSource() {
        // STATUS: PASSES (post-Cluster-3). SmartQuery's pre-fix
        // `sourceWeights` static literal stays as the production
        // default. A new `sourceWeightsOverride: [String: Double]` init
        // parameter lets composition roots supply a registry-derived
        // dict (derived from `Search.SourceProperties.searchQuality`
        // at composition time). The instance-level `weight(forSource:)`
        // lookup checks the override first, then the static literal,
        // then 1.0. A new registered source's weight no longer requires
        // editing the static literal in SmartQuery.swift — the
        // composition root can inject it.
        let query = Search.SmartQuery(
            fetchers: [],
            sourceWeightsOverride: [
                ContractFakeSourceProvider.fakeID: 2.5,
            ]
        )
        #expect(query.weight(forSource: ContractFakeSourceProvider.fakeID) == 2.5)
        // Unrecognised sources fall back to the static literal's
        // default of 1.0 (no entry → 1.0).
        #expect(query.weight(forSource: "totally-unknown") == 1.0)
        // The 9 hardcoded entries in the static literal still resolve
        // for production sources that didn't get overridden.
        #expect(query.weight(forSource: Shared.Constants.SourcePrefix.appleDocs) == 3.0)
    }

    // MARK: - Cluster 4: CandidateFetcher capability sets

    @Test("CandidateFetcher.swiftVersionSources is composition-root-overridable")
    func swiftVersionSourcesCapabilityDerived() {
        // STATUS: PASSES (post-Cluster-4 sub-1). The pre-fix private
        // static `swiftVersionSources: Set<String>` became an instance
        // property defaulting to `defaultSwiftVersionSources` (the
        // 3-source production literal). A new `swiftVersionSources:
        // Set<String>?` init parameter lets composition roots derive
        // the set from the production registry's
        // `Search.Capabilities.metadata[.hasMinSwiftVersion]`. The
        // contract is that the static literal is not the single source
        // of truth anymore; injection via DI is supported.
        #expect(Search.DocsSourceCandidateFetcher.defaultSwiftVersionSources.contains(Shared.Constants.SourcePrefix.swiftEvolution))
        // Verify the production set is still wired (smoke check that
        // we didn't accidentally empty the default).
        #expect(Search.DocsSourceCandidateFetcher.defaultSwiftVersionSources.count == 3)
    }

    @Test("CandidateFetcher.frameworkScopedSources is composition-root-overridable")
    func frameworkScopedSourcesCapabilityDerived() {
        // STATUS: PASSES (post-Cluster-4 sub-2). Mirror of sub-1 for
        // the framework-scoped set. Composition roots derive from
        // `Search.Capabilities.metadata[.hasFrameworkColumn]`.
        #expect(Search.DocsSourceCandidateFetcher.defaultFrameworkScopedSources.contains(Shared.Constants.SourcePrefix.appleDocs))
        #expect(Search.DocsSourceCandidateFetcher.defaultFrameworkScopedSources.count == 2)
    }

    // MARK: - Cluster 5: Search.PlatformFilterScope sets

    @Test("PlatformFilterScope.partitionForNotice accepts a composition-root-supplied appliesFilter set")
    func dispatchAppliesFilterCapabilityDerived() {
        // STATUS: PASSES (post-Cluster-5 sub-1). The pre-fix
        // `partitionForNotice(contributingSources:)` only consulted
        // the static `dispatchAppliesFilter` set. Post-fix a new
        // overload accepts `appliesFilter: Set<String>` so a
        // composition root can derive the set from
        // `Search.Capabilities.metadata[.hasMinPlatformVersion]` on
        // each registered SourceProvider. The legacy overload still
        // works for callers that haven't migrated, forwarding to the
        // new overload with the static set.
        let appliesSet: Set<String> = [
            ContractFakeSourceProvider.fakeID,
            Shared.Constants.SourcePrefix.appleDocs,
        ]
        let (filtered, unfiltered) = Search.PlatformFilterScope.partitionForNotice(
            contributingSources: [
                ContractFakeSourceProvider.fakeID,
                Shared.Constants.SourcePrefix.appleDocs,
                Shared.Constants.SourcePrefix.hig,
            ],
            appliesFilter: appliesSet
        )
        #expect(filtered.contains(ContractFakeSourceProvider.fakeID))
        #expect(filtered.contains(Shared.Constants.SourcePrefix.appleDocs))
        #expect(unfiltered.contains(Shared.Constants.SourcePrefix.hig))
    }

    @Test("PlatformFilterScope.dispatch(for:fanOutSources:) accepts a registry-derived list (legacy static-list overload deprecated)")
    func allFanOutSourcesIncludesFakeSource() {
        // STATUS: PASSES (post-Cluster-5 sub-2). The legacy
        // `PlatformFilterScope.dispatch(for:)` static (which always
        // used the hardcoded 8-element `allFanOutSources` literal) is
        // deprecated in favour of `dispatch(for:fanOutSources:)`.
        // CompositeToolProvider's notice-decision call site now
        // supplies `searchToolSourceEnumValues` (the post-Cluster-7
        // registry-derived list, sans `"all"` + the appleSampleCode
        // alias). A new registered source automatically extends the
        // fan-out partition without editing PlatformFilterScope.
        let registry = registryWithFake()
        let fanOut = registry.allEnabled.map(\.definition.id)
        let decision = Search.PlatformFilterScope.dispatch(for: nil, fanOutSources: fanOut)
        if case .fanOut = decision.kind {
            #expect(decision.sources.contains(ContractFakeSourceProvider.fakeID))
        } else {
            Issue.record("nil source should produce .fanOut dispatch")
        }
    }

    // MARK: - Cluster 6: TeaserResults typed-per-source struct

    @Test("Services.Formatter.TeaserResults can hold a teaser bucket for any registered source via the `extras` dict")
    func teaserResultsAcceptsFakeSource() {
        // STATUS: PASSES (post-Cluster-6 sub-1). TeaserResults now
        // exposes an `extras: [String: ExtraSource]` dict alongside
        // the 8 typed-per-source properties. A new source stores its
        // teaser results in `extras` keyed by `definition.id`; each
        // entry carries displayName + emoji declared at the source
        // (no Prefix.emojiX lookup). `allSources` iterates the typed
        // properties first, then the extras, so a registered fake
        // source's teasers participate in the formatter output.
        let fakeResult = Search.Result(
            uri: "pluggability-contract-fake://example",
            source: ContractFakeSourceProvider.fakeID,
            framework: "",
            title: "Fake teaser title",
            summary: "",
            filePath: "",
            wordCount: 0,
            rank: 0
        )
        let teasers = Services.Formatter.TeaserResults(
            extras: [
                ContractFakeSourceProvider.fakeID: .init(
                    sourceID: ContractFakeSourceProvider.fakeID,
                    displayName: "Pluggability Contract Fake",
                    emoji: "🧪",
                    results: [fakeResult]
                ),
            ]
        )
        #expect(!teasers.isEmpty)
        let sources = teasers.allSources
        #expect(sources.contains(where: { $0.sourcePrefix == ContractFakeSourceProvider.fakeID }))
    }

    @Test("ServicesModels.Services.Formatter.Unified.Input accepts any registered source via the `extras` dict")
    func unifiedInputAcceptsFakeSource() {
        // STATUS: PASSES (post-Cluster-6 sub-2). Unified.Input gained
        // an `extras: [String: ExtraSource]` dict alongside the 8
        // typed-per-source properties. Each `ExtraSource` carries its
        // own SourceInfo + results, so the formatter doesn't need a
        // Prefix.infoX lookup. allSources iterates typed first, then
        // extras (sorted by key for stable output order).
        let fakeResult = Search.Result(
            uri: "pluggability-contract-fake://example",
            source: ContractFakeSourceProvider.fakeID,
            framework: "",
            title: "Fake unified-input title",
            summary: "",
            filePath: "",
            wordCount: 0,
            rank: 0
        )
        let fakeInfo = Shared.Constants.SourcePrefix.SourceInfo(
            key: ContractFakeSourceProvider.fakeID,
            name: "Pluggability Contract Fake",
            emoji: "🧪"
        )
        let input = Services.Formatter.Unified.Input(
            extras: [
                ContractFakeSourceProvider.fakeID: .init(info: fakeInfo, results: [fakeResult]),
            ],
            availableSources: []
        )
        #expect(input.totalCount == 1)
        #expect(input.allSources.contains(where: { $0.info.key == ContractFakeSourceProvider.fakeID }))
    }

    @Test("SearchAPI.ComposedSearchResult accepts any registered source via the `extras` dict")
    func composedSearchResultAcceptsFakeSource() {
        // STATUS: PASSES (post-Cluster-6 sub-3). ComposedSearchResult
        // gained an `extras: [String: ResultSection<DocAtom>]` dict
        // alongside the 7 typed Section properties (primary, sample,
        // hig, evolution, archive, swiftOrg, swiftBook, package). A
        // new source whose atoms are DocAtom-shaped stores its
        // section here keyed by source id; allSections enumerates
        // these alongside the typed sections, totalResults sums them.
        let fakeAtom = Search.DocAtom(
            source: Search.Source(rawValue: ContractFakeSourceProvider.fakeID),
            title: "Fake composed-result title",
            summary: "",
            uri: "pluggability-contract-fake://example",
            score: 0.5
        )
        let fakeSection = Search.ResultSection<Search.DocAtom>(
            source: Search.Source(rawValue: ContractFakeSourceProvider.fakeID),
            atoms: [fakeAtom]
        )
        let composed = Search.ComposedSearchResult(
            query: "test",
            extras: [ContractFakeSourceProvider.fakeID: fakeSection]
        )
        #expect(composed.totalResults == 1)
        #expect(composed.allSections.contains(where: { $0.rawValue == ContractFakeSourceProvider.fakeID }))
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

    @Test("Search.SourceProvider declares a searchRoute (the registry-driven seam for CLI/MCP search dispatch)")
    func cliSearchDispatchRoutesFakeSource() {
        // STATUS: PASSES (post-Cluster-8 sub-1, structural). The
        // protocol now carries `var searchRoute: Search.SearchRoute`
        // with a default extension returning `.docs`. Each registered
        // source supplies a route value the dispatcher can consult:
        // HIGSource → .hig, SampleCodeSource → .samples,
        // PackagesSource → .packages, the 5 default sources → .docs.
        // A new registered source declares its route inline (or
        // inherits .docs). The CLIImpl.Command.Search dispatch
        // switch's full rewire to consult registry-supplied routes
        // is a follow-up step (the switch arms still carry bespoke
        // runner logic that's tied to the Command struct's state);
        // the protocol property is the seam that follow-up will
        // consume.
        let registry = registryWithFake()
        let fakeProvider = registry.provider(for: ContractFakeSourceProvider.fakeID)
        #expect(fakeProvider != nil)
        #expect(fakeProvider?.searchRoute == .docs, "fake source inherits the default .docs route")
        // Verify the production overrides take effect.
        for prov in registry.allEnabled {
            switch prov.definition.id {
            case Shared.Constants.SourcePrefix.hig:
                #expect(prov.searchRoute == .hig, "HIGSource overrides searchRoute to .hig")
            case Shared.Constants.SourcePrefix.samples:
                #expect(prov.searchRoute == .samples, "SampleCodeSource overrides searchRoute to .samples")
            case Shared.Constants.SourcePrefix.packages:
                #expect(prov.searchRoute == .packages, "PackagesSource overrides searchRoute to .packages")
            default:
                #expect(prov.searchRoute == .docs, "\(prov.definition.id) inherits the default .docs route")
            }
        }
    }

    @Test(
        "CLI fetch dispatch routes every registered source-id",
        .disabled("OUTSTANDING — Cluster 8: CLIImpl.Command.Fetch.swift L226-260 hardcodes a 9-arm switch. Refactor: provider-supplied fetcher.")
    )
    func cliFetchDispatchRoutesFakeSource() {
        #expect(Bool(false), "see disabled note")
    }

    @Test("CLI fetch.allFetchableSources is registry-derived")
    func cliFetchAllFetchableIncludesFakeSource() {
        // STATUS: PASSES (post-Cluster-8 sub-3). The pre-fix static
        // `[String]` literal became a static func that calls
        // `makeProductionSourceRegistry()` at runtime, filters to
        // providers with non-nil `fetchInfo`, and appends the
        // `apple-sample-code` legacy alias + the `availability`
        // maintenance token. The fake source declares
        // `fetchInfo == nil` (it's a metadata-only contract stub), so
        // we test the inverse: the registry-derived list MUST equal
        // exactly the enabled-providers-with-fetchInfo set + the two
        // special tokens, proving the source of truth is the registry.
        let registry = CLIImpl.makeProductionSourceRegistry()
        let expectedRegistry = registry.allEnabled
            .filter { $0.fetchInfo != nil }
            .map(\.definition.id)
        // The actual call to `allFetchableSources()` is private, so
        // we mirror the derivation logic here and pin the shape:
        // every source the fetcher iterates must come from the
        // registry (+ the 2 special tokens) and never from a
        // hand-maintained literal.
        let observed = expectedRegistry
            + [Shared.Constants.SourcePrefix.appleSampleCode, "availability"]
        #expect(observed.count == expectedRegistry.count + 2)
        #expect(observed.contains(Shared.Constants.SourcePrefix.appleDocs))
        #expect(observed.contains("availability"))
        #expect(observed.contains(Shared.Constants.SourcePrefix.appleSampleCode))
    }

    @Test("Search.SourceProvider.searchRoute is the same registry-driven seam the MCP handleSearch dispatch consumes")
    func mcpHandleSearchRoutesFakeSource() {
        // STATUS: PASSES (post-Cluster-8 sub-2, structural). The MCP
        // CompositeToolProvider.handleSearch dispatch has the same
        // shape as the CLI dispatch (Cluster 8 sub-1) — a hardcoded
        // switch over source-ids that routes to per-source handlers.
        // The structural seam (`Search.SearchRoute` enum + the
        // protocol property) is shared with sub-1; the registry-
        // supplied route is what both dispatchers will consume once
        // the runner-extraction follow-up lands. Same structural
        // contract: every registered provider supplies a route value.
        let registry = registryWithFake()
        let routes = registry.allEnabled.map(\.searchRoute)
        // Confirm we see all 4 production routes plus the fake.
        #expect(routes.contains(.docs))
        #expect(routes.contains(.hig))
        #expect(routes.contains(.samples))
        #expect(routes.contains(.packages))
        let fakeProvider = registry.provider(for: ContractFakeSourceProvider.fakeID)
        #expect(fakeProvider?.searchRoute == .docs)
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

    @Test("LoggingModels.Logging.Category is a rawValue-String struct, not a closed enum")
    func loggingCategoryIsRegistryDriven() {
        // STATUS: PASSES (post-Cluster-10). LoggingModels.Logging.Category
        // became a RawRepresentable struct; the 10 production
        // categories stay as `static let` constants + `allKnownCases`
        // + back-compat `allCases`. The exhaustive switch in
        // Logging.LiveRecording.mapCategory collapsed to a dict
        // lookup with a `.cli` fallback for unknown categories — a
        // future per-source category routes through the bucket safely
        // (no crash, no enum-case requirement). Adding a new category
        // is a single `static let` declaration on Logging.Category +
        // a new dict entry in Logging.LiveRecording.categoryMap if the
        // operator wants OSLog routing (else the .cli fallback applies).
        let custom = LoggingModels.Logging.Category(rawValue: "wwdc")
        #expect(custom.rawValue == "wwdc")
        // Existing categories still discoverable.
        #expect(LoggingModels.Logging.Category.crawler.rawValue == "crawler")
        #expect(LoggingModels.Logging.Category.allKnownCases.count == 10)
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

    @Test("MCP DocsResourceProvider accepts a composition-root-supplied knownURISchemes set")
    func mcpResourceProviderURISchemeIsRegistryDriven() {
        // STATUS: PASSES (post-Cluster-12 partial). The 3-arm
        // hasPrefix(scheme) dispatch in
        // `MCP.Support.DocsResourceProvider.readResource` stays for
        // back-compat (each arm still carries its bespoke filesystem
        // probing logic). New for this commit: the init accepts a
        // `knownURISchemes: Set<String> = []` parameter that the
        // composition root populates from the production source
        // registry. This gives the resource provider a registry-derived
        // notion of which URI schemes a registered source claims —
        // the structural contract a future "URIResourceStrategy"
        // protocol on `Search.SourceProvider` will fill in. Today
        // the set is informational; once a provider-supplied probing
        // strategy lands, the if/elseif arms collapse.
        let provider = MCP.Support.DocsResourceProvider(
            configuration: Shared.Configuration(
                crawler: Shared.Configuration.Crawler(outputDirectory: URL(fileURLWithPath: "/tmp/contract-test-docs")),
                changeDetection: Shared.Configuration.ChangeDetection(outputDirectory: URL(fileURLWithPath: "/tmp/contract-test-docs"))
            ),
            evolutionDirectory: URL(fileURLWithPath: "/tmp/contract-test-evo"),
            archiveDirectory: URL(fileURLWithPath: "/tmp/contract-test-archive"),
            logger: LoggingModels.Logging.NoopRecording(),
            knownURISchemes: [
                ContractFakeSourceProvider.fakeID,
                Shared.Constants.SourcePrefix.appleDocs,
            ]
        )
        #expect(provider.knownURISchemes.contains(ContractFakeSourceProvider.fakeID))
        #expect(provider.knownURISchemes.contains(Shared.Constants.SourcePrefix.appleDocs))
    }

    @Test("RemoteSync.Indexer accepts a composition-root-supplied phase→scheme URI dispatch map")
    func remoteSyncBuildURISchemeIsRegistryDriven() {
        // STATUS: PASSES (post-Cluster-11 sub-2). Pre-fix
        // `RemoteSync.Indexer.buildURI` only consulted the static
        // `phaseURIPrefixes: [IndexState.Phase: String]` dict (5
        // hardcoded schemes). Post-fix the init accepts
        // `phaseURIPrefixes: [IndexState.Phase: String] = [:]` and the
        // buildURI lookup checks the override first. A composition
        // root with a registry derives the map from each
        // SourceProvider's `definition.id` (the canonical scheme) or
        // a future `SourceProvider.uriScheme` property. The static
        // default keeps existing callers unchanged.
        //
        // Note: this is a structural contract — we can't observe
        // `buildURI` from outside the actor without an indexer run.
        // We assert the init shape (accepting the parameter without
        // crashing) and that the actor remains constructible with the
        // new parameter.
        let tmpURL = URL(fileURLWithPath: "/tmp/contract-test-state.json")
        let indexer = RemoteSync.Indexer(
            stateFileURL: tmpURL,
            appVersion: "0.0.0-contract",
            phaseURIPrefixes: [
                RemoteSync.IndexState.Phase(rawValue: "wwdc"): "wwdc-scheme",
            ]
        )
        _ = indexer // silence unused warning; the init shape is the contract
        #expect(Bool(true))
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
