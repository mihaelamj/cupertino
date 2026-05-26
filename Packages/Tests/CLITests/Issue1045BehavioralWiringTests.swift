// swiftlint:disable line_length
// (descriptive STATUS comments inside each test exceed the 120-char line guideline; readability beats wrapping here.)

@testable import CLI
import Foundation
import IndexerModels
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import ServicesModels
import SharedConstants
import Testing

// MARK: - #1045 behavioural wiring proof

//
// `Issue1042PluggabilityContractTests` asserts that structural seams
// exist (override parameter declared, closed enum became RawRepresentable,
// etc.). That suite caught the original audit's "26/26 green" claim
// passing while production composition roots silently fell back to
// static-literal defaults.
//
// This file is the BEHAVIOURAL counterpart: each test registers a fake
// source with explicit metadata, mirrors the production composition-
// root logic in-test, and asserts the registry-supplied value actually
// flows. If the production code stops passing the override at the call
// site (a regression of the original audit's finding), the behavioural
// assertion fails.
//

private struct GapWiringFake: Search.SourceProvider {
    static let fakeID = "issue-1045-behavioural-fake"
    let rankWeightValue: Double
    let dockindRaw: String?
    let fetchInfoValue: Search.FetchInfo?

    init(
        rankWeight: Double = 1.0,
        defaultDocKindRawValue: String? = nil,
        fetchInfo: Search.FetchInfo? = nil
    ) {
        rankWeightValue = rankWeight
        dockindRaw = defaultDocKindRawValue
        fetchInfoValue = fetchInfo
    }

    var definition: Search.SourceDefinition {
        Search.SourceDefinition(
            id: Self.fakeID,
            displayName: "Issue 1045 Behavioural Fake",
            emoji: "🧪",
            properties: Search.SourceProperties(
                authority: 0.5,
                freshness: 0.5,
                comprehensiveness: 0.5,
                codeExamples: 0.5,
                hasAvailability: 0.5,
                designFocus: 0.5,
                languageFocus: 0.5,
                searchQuality: 0.5,
                rankWeight: rankWeightValue
            ),
            intents: [.howTo],
            defaultDocKindRawValue: dockindRaw
        )
    }

    var destinationDB: Shared.Models.DatabaseDescriptor { .swiftOrg }
    var fetchInfo: Search.FetchInfo? { fetchInfoValue }
    var capabilities: Search.Capabilities {
        Search.Capabilities(searchers: [.text], operations: [.readByURI])
    }

    var legacySourceIDAliases: Set<String> { [] }
    func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        preconditionFailure("Behavioural wiring tests never invoke makeStrategy")
    }

    func makeIndexer() -> any Search.SourceIndexer {
        preconditionFailure("Behavioural wiring tests never invoke makeIndexer")
    }
}

@Suite("Issue #1045 — behavioural wiring of all 4 acceptance criteria")
struct Issue1045BehavioralWiringTests {
    private func registryWith(_ fake: GapWiringFake) -> Search.SourceRegistry {
        var registry = CLIImpl.makeProductionSourceRegistry()
        registry.register(fake)
        return registry
    }

    // MARK: - Gap 1 — SmartQuery rankWeight wiring

    @Test("Gap 1 — `CLIImpl.makeSmartQuerySourceWeights` produces the dict SmartQuery consumes")
    func gap1_rankWeightThreadsToSmartQuery() {
        // STATUS: behavioural. The production CLI path
        // (CLIImpl.Command.Search.run) calls
        // `CLIImpl.makeSmartQuerySourceWeights(registry:)` — the same
        // helper we call here. The grep test
        // (Issue1045ProductionCallSiteTests) pins the CLI source file
        // to keep calling the helper; this test pins the helper's
        // behaviour. Together they cover the wiring end-to-end.
        let fake = GapWiringFake(rankWeight: 2.7)
        let registry = registryWith(fake)
        let weights = CLIImpl.makeSmartQuerySourceWeights(registry: registry)
        let query = Search.SmartQuery(fetchers: [], sourceWeightsOverride: weights)
        #expect(query.weight(forSource: GapWiringFake.fakeID) == 2.7)
        // Sanity: the override doesn't break the existing production
        // weights (e.g. apple-docs's 3.0 still wins).
        #expect(query.weight(forSource: Shared.Constants.SourcePrefix.appleDocs) == 3.0)
    }

    // MARK: - Gap 3 — DocKind via SourceLookup string seam

    @Test("Gap 3 — registered provider's defaultDocKindRawValue resolves through Classify.kind")
    func gap3_docKindRawValueResolvesThroughClassifier() {
        // STATUS: behavioural. Fake declares defaultDocKindRawValue =
        // "evolutionProposal" (a real DocKind rawValue). The
        // production wiring (commit 31516a06) passes
        // sourceLookup.docKindRawValuesByID to Search.Classify.kind.
        // We assemble the dict the same way and assert the fake's
        // source-id resolves to the matching DocKind via init(rawValue:).
        let fake = GapWiringFake(defaultDocKindRawValue: "evolutionProposal")
        let registry = registryWith(fake)
        let docKindMap = CLIImpl.makeDocKindRawValuesByID(registry: registry)
        #expect(docKindMap[GapWiringFake.fakeID] == "evolutionProposal")
        let resolved = Search.Classify.kind(
            source: GapWiringFake.fakeID,
            docKindByID: docKindMap
        )
        #expect(resolved == .evolutionProposal)
        // Sanity: production sources still resolve via the dict path
        // (not the legacy switch fallback). HIG declares "hig" → .hig.
        let higResolved = Search.Classify.kind(
            source: Shared.Constants.SourcePrefix.hig,
            docKindByID: docKindMap
        )
        #expect(higResolved == .hig)
    }

    @Test("Gap 3 — nil-rawValue provider falls back to legacy switch (apple-docs bespoke path stays load-bearing)")
    func gap3_nilRawValueFallsBackToLegacySwitch() {
        // STATUS: behavioural. Fake declares nil. The dict omits it.
        // Classify.kind falls through to the legacy switch's default
        // arm → .unknown. apple-docs's bespoke classifier path
        // (classifyAppleDocs partitioning by structuredKind) still
        // fires for that source because the dict only contains
        // sources with non-nil rawValues.
        let fake = GapWiringFake(defaultDocKindRawValue: nil)
        let registry = registryWith(fake)
        let docKindMap = CLIImpl.makeDocKindRawValuesByID(registry: registry)
        #expect(docKindMap[GapWiringFake.fakeID] == nil)
        let resolved = Search.Classify.kind(
            source: GapWiringFake.fakeID,
            docKindByID: docKindMap
        )
        #expect(resolved == .unknown)
        // Sanity: apple-docs still goes through its bespoke classifier
        // even when the lookup is supplied. Its dict entry is nil
        // (AppleDocsSource declares defaultDocKindRawValue: nil), so
        // the switch's appleDocs arm fires.
        let appleResolved = Search.Classify.kind(
            source: Shared.Constants.SourcePrefix.appleDocs,
            structuredKind: "protocol",
            uriPath: "/documentation/swiftui/view",
            docKindByID: docKindMap
        )
        #expect(appleResolved == .symbolPage)
    }

    // MARK: - Gap 4 — DocsIndexingInput.directoryByKey wiring

    @Test("Gap 4 audit follow-up (14.5) — CLI --docs-dir override layered through makeDocsIndexingDirectoryByKey wins over the registry default")
    func gap4_cliOverrideWinsOverRegistryDefault() {
        // STATUS: behavioural. Post-audit (Finding 14.5) the helper
        // accepts an `overrides: [String: URL?]` parameter so the
        // CLI's `--docs-dir /custom` flag can win over the registry
        // default. Pre-fix the dict ALWAYS won, silently dropping
        // the user's override.
        let registry = CLIImpl.makeProductionSourceRegistry()
        let paths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/issue-1045-override"))
        let customDocs = URL(fileURLWithPath: "/tmp/my-custom-docs")
        let dict = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: registry,
            paths: paths,
            overrides: [
                Shared.Constants.SourcePrefix.appleDocs: customDocs,
            ]
        )
        // Override wins: apple-docs entry equals /tmp/my-custom-docs
        // (symlink-resolved — `.resolvingSymlinksInPath()` is a no-op
        // for non-symlink paths).
        if let entry = dict[Shared.Constants.SourcePrefix.appleDocs], let resolved = entry {
            #expect(resolved.path == customDocs.resolvingSymlinksInPath().path)
        } else {
            Issue.record("apple-docs override should resolve to a non-nil URL; got \(String(describing: dict[Shared.Constants.SourcePrefix.appleDocs]))")
        }
        // Sanity: other registered sources still fall back to registry defaults.
        if let higEntry = dict[Shared.Constants.SourcePrefix.hig], let url = higEntry {
            #expect(url.path.contains("hig"))
        } else {
            Issue.record("hig should resolve to its registry-default directory; got \(String(describing: dict[Shared.Constants.SourcePrefix.hig]))")
        }
    }

    @Test("Gap 4 — registered provider's fetchInfo.outputDir reaches DocsIndexingInput.directoryByKey")
    func gap4_fetchInfoOutputDirThreadsToInput() {
        // STATUS: behavioural. Fake declares a fetchInfo with
        // defaultOutputDirKey = "behavioural-fake-dir". The Save
        // composition root (commit 25a660c4) walks registry.allEnabled,
        // resolves provider.fetchInfo.defaultOutputDirKey.rawValue
        // against Shared.Paths.directory(named:), builds [String: URL?]
        // and threads it via Indexer.DocsService.Request.directoryByKey →
        // Search.DocsIndexingInput.directoryByKey. We mirror that
        // assembly in-test and assert the fake's source-id maps to the
        // expected URL.
        let fakeOutputKey = Search.FetchInfo.DefaultOutputDirKey(rawValue: "behavioural-fake-dir")
        let fakeFetchInfo = Search.FetchInfo(
            displayName: "Behavioural Fake",
            sourceID: GapWiringFake.fakeID,
            crawlBaseURLs: [],
            defaultOutputDirKey: fakeOutputKey,
            isWebCrawlable: false
        )
        let fake = GapWiringFake(fetchInfo: fakeFetchInfo)
        let registry = registryWith(fake)
        let savePaths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/issue-1045-behavioural"))
        let dict = CLIImpl.makeDocsIndexingDirectoryByKey(
            registry: registry,
            paths: savePaths
        )
        let expected = savePaths.directory(named: "behavioural-fake-dir")
        #expect(dict[GapWiringFake.fakeID] == expected)
        // Sanity: a registered production source's directory also
        // resolves through the dict (apple-docs's defaultOutputDirKey
        // is .docs → /tmp/.../docs).
        if let appleDocsURL = dict[Shared.Constants.SourcePrefix.appleDocs], let url = appleDocsURL {
            #expect(url.lastPathComponent == "docs")
        } else {
            Issue.record("AppleDocsSource's directory should resolve via the dict; got nil entry")
        }
    }

    // MARK: - Gap 2 — Footer availableSources end-to-end

    @Test("Gap 2 — registered provider's id reaches Footer.Search.allSourcesDiscovery via the production formatter wiring")
    func gap2_availableSourcesReachesFooter() {
        // STATUS: behavioural. The production CLI wiring (commit
        // a81b2678) at CLIImpl.Command.Search.SourceRunners builds:
        //   let registeredSources = CLIImpl.makeProductionSourceRegistry()
        //                              .allEnabled.map(\.definition.id)
        // and threads it through every formatter's `availableSources:`
        // parameter. We mirror that and render the footer to confirm
        // the fake's id appears in the "All sources you can search" block.
        let fake = GapWiringFake()
        let registry = registryWith(fake)
        let registeredSources = CLIImpl.makeFormatterAvailableSources(registry: registry)
        let footer = Services.Formatter.Footer.Search.unified(
            availableSources: registeredSources
        )
        let rendered = footer.formatText()
        #expect(rendered.contains(GapWiringFake.fakeID))
        // The legacy "_To narrow results, use `source` parameter: …_"
        // tip joins the registered list with `, `; the new
        // .allSourcesDiscovery block joins with ` · `. Either form is
        // acceptable — assert the fakeID appears, not the format.
    }

    // MARK: - Sanity: production registry is reachable

    @Test("Production registry exists and includes the 8 shipped sources")
    func productionRegistrySanity() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let ids = Set(registry.allEnabled.map(\.definition.id))
        #expect(ids.contains(Shared.Constants.SourcePrefix.appleDocs))
        #expect(ids.contains(Shared.Constants.SourcePrefix.hig))
        #expect(ids.contains(Shared.Constants.SourcePrefix.samples))
        #expect(ids.contains(Shared.Constants.SourcePrefix.packages))
        #expect(ids.contains(Shared.Constants.SourcePrefix.appleArchive))
        #expect(ids.contains(Shared.Constants.SourcePrefix.swiftEvolution))
        #expect(ids.contains(Shared.Constants.SourcePrefix.swiftOrg))
        #expect(ids.contains(Shared.Constants.SourcePrefix.swiftBook))
        #expect(ids.count == 8)
    }
}
