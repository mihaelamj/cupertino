// swiftlint:disable line_length
// (descriptive @Test annotations + #expect failure messages exceed the 120-char line guideline; readability beats wrapping here.)

@testable import CLI
import CupertinoComposition
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - Pluggability invariant audit (per `feedback_sources_100pct_pluggable` memory)

//
// The load-bearing claim of the per-source DB split epic: **adding a
// new source = one PR that touches the source's own files + one line
// at the composition root + one manifest yaml**. Same standard for new
// DBs: **adding a new DB = one new `DatabaseDescriptor` static + one
// flip of the source's `destinationDB` property**.
//
// This suite is the mechanical test of that claim. It defines a fake
// `Search.SourceProvider` conformer entirely inside the test target,
// constructs a `Search.SourceRegistry` containing the fake (no
// production code modified), and verifies every consumer the
// composition root depends on accepts the fake transparently:
//
//   - Search.SourceRegistry.register(...) accepts the new provider
//   - registry.entry(for:) resolves the fake by id
//   - registry.allEnabled iterates including the fake
//   - destinationDB grouping correctly assigns the fake to a new DB
//   - capability declarations on the fake flow through the registry
//   - the indexer dict + strategies list assembly logic (mirrored from
//     CLIImpl.Command.Save.Indexers) includes the fake
//
// If ANY of these fail, the 2-file PR claim is broken: a real new
// source would silently fail at one of these seams. The whole point
// of the split epic.
//
// If new failures appear here later (e.g. a step-5+ refactor adds a
// new consumer that the fake doesn't satisfy), THIS suite is what
// catches the regression at PR review time.

@Suite("Pluggability invariant: a fake SourceProvider plugs in without touching existing concretes")
struct PluggabilityInvariantTests {
    // MARK: - The fake source

    /// Hypothetical "audit-fixture" source. Lives entirely in this
    /// test file; no production target touched. Models what a
    /// minimal real-world new source would look like.
    fileprivate struct AuditFixtureSource: Search.SourceProvider {
        var definition: Search.SourceDefinition {
            Search.SourceDefinition(
                id: "audit-fixture",
                displayName: "Audit Fixture",
                emoji: "🧪",
                properties: Search.SourceProperties(
                    authority: 0.5,
                    freshness: 0.5,
                    comprehensiveness: 0.5,
                    codeExamples: 0.0,
                    hasAvailability: 0.0,
                    designFocus: 0.0,
                    languageFocus: 0.0,
                    searchQuality: 0.5
                ),
                intents: [.apiReference]
            )
        }

        var fetchInfo: Search.FetchInfo? {
            Search.FetchInfo(
                displayName: "Audit Fixture",
                sourceID: "audit-fixture",
                crawlBaseURLs: ["https://example.invalid/audit/"],
                defaultOutputDirKey: .docs,
                isWebCrawlable: true
            )
        }

        var destinationDB: Shared.Models.DatabaseDescriptor {
            // Models the "new DB" case: a brand-new descriptor the fake
            // declares. In a real PR this would land alongside a new
            // `DatabaseDescriptor` static; here we synthesise one inline
            // to test the "1-line new-DB add" half of the invariant.
            Shared.Models.DatabaseDescriptor(
                id: "audit-fixture",
                filename: "audit-fixture.db",
                displayName: "Audit Fixture DB"
            )
        }

        var capabilities: Search.Capabilities {
            .init(
                searchers: [.text, .symbols],
                operations: [.readByURI],
                metadata: [.hasMinPlatformVersion: true]
            )
        }

        func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
            FakeStrategy()
        }

        func makeIndexer() -> any Search.SourceIndexer {
            FakeIndexer()
        }
    }

    fileprivate struct FakeStrategy: Search.SourceIndexingStrategy {
        let source = "audit-fixture"

        func indexItems(
            into _: any Search.Database & Search.IndexWriter,
            progress _: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats {
            Search.IndexStats(source: source, indexed: 0, skipped: 0, wasSkipped: true, skipReason: "audit fixture")
        }
    }

    fileprivate struct FakeIndexer: Search.SourceIndexer {
        var sourceID: String {
            "audit-fixture"
        }

        var displayName: String {
            "Audit Fixture"
        }

        func extractCode(documentID _: Int, content _: String, uri _: String, defaultFramework _: String?) -> Search.ExtractedContent? {
            nil
        }
    }

    // MARK: - Audit checks (each test = one seam the new source must pass through)

    @Test("Seam 1: Search.SourceRegistry.register accepts the fake provider with zero ceremony")
    func registryAccepts() {
        var registry = Search.SourceRegistry()
        registry.register(AuditFixtureSource())
        #expect(registry.allEnabled.count == 1)
        #expect(registry.allEnabled.first?.definition.id == "audit-fixture")
    }

    @Test("Seam 2: registry.entry(for:) resolves the fake by id")
    func entryLookupResolvesFake() {
        var registry = Search.SourceRegistry()
        registry.register(AuditFixtureSource())
        let entry = registry.entry(for: "audit-fixture")
        #expect(entry != nil)
        #expect(entry?.provider.definition.displayName == "Audit Fixture")
    }

    @Test("Seam 3: fake's destinationDB is a fresh DatabaseDescriptor distinct from every existing one")
    func destinationDBIsFresh() {
        let fake = AuditFixtureSource()
        let existingDescriptors: [Shared.Models.DatabaseDescriptor] = [
            .search, .samples, .packages,
            .appleDocumentation, .hig, .appleArchive,
            .swiftEvolution, .swiftDocumentation,
            .appleSampleCode, .swiftPackages,
        ]
        #expect(!existingDescriptors.contains(fake.destinationDB), "fake's destinationDB collides with an existing static; new-DB invariant broken")
        #expect(fake.destinationDB.id == "audit-fixture")
        #expect(fake.destinationDB.filename == "audit-fixture.db")
    }

    @Test("Seam 4: capability declarations flow through the registry intact")
    func capabilitiesFlow() throws {
        var registry = Search.SourceRegistry()
        registry.register(AuditFixtureSource())
        let entry = try #require(registry.entry(for: "audit-fixture"))
        let resolved = entry.provider.capabilities
        #expect(resolved.searchers == [.text, .symbols])
        #expect(resolved.operations == [.readByURI])
        #expect(resolved.metadata[Search.Capabilities.MetadataFlag.hasMinPlatformVersion] == true)
    }

    @Test("Seam 5: dispatcher's indexer-dict assembly logic (per Save.Indexers) includes the fake")
    func indexerDictAssemblyIncludesFake() {
        var registry = Search.SourceRegistry()
        for provider in CLIImpl.makeProductionSourceRegistry().allEnabled {
            registry.register(provider)
        }
        registry.register(AuditFixtureSource())

        // Mirror the post-step-4 transitional filter at
        // CLIImpl.Command.Save.Indexers.swift:264 + :353 ("!= .packages").
        let derivedDict: [String: any Search.SourceIndexer] = registry.allEnabled
            .filter { $0.destinationDB != .packages }
            .reduce(into: [:]) { dict, provider in
                dict[provider.definition.id] = provider.makeIndexer()
            }
        #expect(derivedDict["audit-fixture"] != nil, "fake's indexer must appear in the dispatch dict")
        #expect(derivedDict.count == 8, "8 production sources - 1 (packages filtered) + 1 fake = 8 keys")
    }

    @Test("Seam 6: step-5 future dispatcher (Dictionary(grouping: by: destinationDB)) routes the fake to its OWN DB group")
    func futureGroupingDispatchRoutesFakeToOwnGroup() {
        var registry = Search.SourceRegistry()
        for provider in CLIImpl.makeProductionSourceRegistry().allEnabled {
            registry.register(provider)
        }
        registry.register(AuditFixtureSource())

        // Group by the full DatabaseDescriptor value (matching the
        // sketched step-5 dispatcher at docs/design/per-source-db-split.md
        // §5; the doc keys on the full descriptor, not just the id, so
        // a future regression where two sources accidentally share an
        // `id` but diverge on filename/displayName partitions correctly).
        let grouped: [Shared.Models.DatabaseDescriptor: [any Search.SourceProvider]] =
            Dictionary(grouping: registry.allEnabled, by: { $0.destinationDB })
        let fakeDescriptor = AuditFixtureSource().destinationDB
        #expect(grouped[fakeDescriptor]?.count == 1, "fake must be the sole occupant of its destinationDB group; no leak from existing sources")
        // Sanity: existing sources still group as expected post step 4.
        #expect(grouped[.packages]?.count == 1)
        #expect(grouped[.appleDocumentation]?.count == 1)
        // Post #1038 ("diff db for each source"), swift-org and
        // swift-book each own their own DB; the pre-#1038 view-source
        // co-location in .swiftDocumentation is gone.
        #expect(grouped[.swiftOrg]?.count == 1, "SwiftOrgSource alone post #1038")
        #expect(grouped[.swiftBook]?.count == 1, "SwiftBookSource alone post #1038")
        #expect(grouped[.swiftDocumentation] == nil, "post #1038 no provider targets the legacy .swiftDocumentation descriptor")
        #expect(
            grouped[.appleSampleCode]?.count == 1,
            "SampleCodeSource at .appleSampleCode (one-DB collapse: shares samples.db with Sample.Index.Builder)"
        )
        #expect(grouped[.search] == nil, "post step-7a flip, no provider is at .search")
    }

    @Test("Seam 7: fake's indexer concrete returns the right source-id tag (no leak through existing types)")
    func indexerCarriesFakeSourceID() {
        let fake = AuditFixtureSource()
        let indexer = fake.makeIndexer()
        #expect(indexer.sourceID == "audit-fixture")
        #expect(indexer.displayName == "Audit Fixture")
        // Strategy construction not verified here because Search.IndexEnvironment
        // requires non-nil markdownStrategy + logger that the fake doesn't ship;
        // strategy.source is verified inline in FakeStrategy = "audit-fixture".
    }

    // MARK: - The PR-file-touch floor, recorded

    @Test("Real-world new-source PR floor: 5 new files + 2 line edits, PLUS the pre-existing closed-set edits documented below")
    func newSourcePRFloorRecorded() {
        // **Per-source target shape today (cross-checked against e.g.
        // ls Packages/Sources/AppleArchiveSource/, 5 files):**
        //
        //   1. Packages/Sources/<X>Source/<X>Source.swift
        //      (SourceProvider conformer; computed-property properties
        //       reference per-source `Self.definition`, `Self.fetchInfo`)
        //   2. Packages/Sources/<X>Source/<X>Source.Definition.swift
        //      (Search.SourceDefinition static literal)
        //   3. Packages/Sources/<X>Source/<X>Source.FetchInfo.swift
        //      (Search.FetchInfo static literal, if fetch-bound)
        //   4. Packages/Sources/<X>Source/Search.<X>Indexer.swift
        //      (Search.SourceIndexer concrete)
        //   5. Packages/Sources/<X>Source/Search.Strategies.<X>.swift
        //      (Search.SourceIndexingStrategy concrete)
        //
        // Plus: docs/sources/<id>/manifest.yaml (new file)
        //
        // Single-line edits to existing files (THIS branch's state):
        //   a. Packages/Package.swift: new SPM target declaration +
        //      one line under cupertinoTargets
        //   b. Packages/Sources/CLI/CLIImpl.SourceRegistry.swift:
        //      one `registry.register(<X>Source())` line
        //
        // PLUS pre-existing closed-set edit sites (Independence Day
        // epic, tracked at github.com/mihaelamj/cupertino issues
        // #932/#933/#934/#935; NOT closed by this branch):
        //
        //   c. Shared.Constants.SourcePrefix.allPrefixes array
        //      (Shared.Constants.swift): one append; consumed by
        //      Search.Index URI-prefix query parsing
        //   d. Search.FetchInfo.DefaultOutputDirKey closed enum +
        //      CLIImpl.Command.Fetch.swift resolveDirectory exhaustive
        //      switch + Shared.Paths accessor (3 edits, if the new
        //      source needs its own output directory)
        //   e. Search.CandidateFetcher swiftVersionSources /
        //      frameworkScopedSources static Set<String> policy
        //      literals (1-2 edits, depending on the new source's
        //      semantics)
        //   f. Logging.Category closed enum
        //      (Logging.LiveRecording.swift exhaustive switch) = 1 edit
        //
        // **For a new DB descriptor (declared by the new source via
        //   destinationDB), ADD:**
        //
        //   g. Shared.Constants.FileName.<X>Database: 1 entry
        //   h. Shared.Models.DatabaseDescriptor.<X> static: 1 entry
        //
        //   PLUS pre-existing closed-list append sites that any new
        //   DB still has to edit (Independence Day #935):
        //
        //   i. Distribution.SetupService.Request.required array
        //      (Setup.swift) = 1 edit; tells setup what to download
        //   j. Doctor.healthChecks array (Doctor.swift) = 1 edit;
        //      tells doctor what to validate
        //   k. Doctor.printSchemaVersions entries array (Doctor.swift) = 1 edit;
        //      tells doctor what schema version to print
        //
        // **Floor (this branch's state, no Independence Day closures
        //  shipped):**
        //
        //   - New source: 5 new files + 1 manifest + 2 single-line
        //     edits + up to 5 closed-set edits (a-f above) = up to 13
        //     PR touches.
        //   - New DB: 2 single-line edits (g-h) + 3 closed-list
        //     edits (i-k) = 5 PR touches.
        //
        // The original `feedback_sources_100pct_pluggable` "2-file PR"
        // framing is the END STATE the Independence Day epic is
        // chasing; today's floor is materially higher. The other
        // tests in this suite verify the seams that ARE pluggable
        // today; the closed-set seams listed above are tracked as
        // separate work that this audit does NOT assert on.
        //
        // When #932-#935 close, this comment should be updated to
        // reflect the new (lower) floor + the corresponding test
        // sites that became unconditionally pluggable.
        #expect(true)
    }

    // MARK: - Drift detectors: foundation-tier static lists must match the production registry

    @Test("Drift detector: Shared.Constants.SourcePrefix.allPrefixes matches every registered source's id (post-2026-05-26 audit Finding 9.2)")
    func sourcePrefixAllPrefixesMatchesRegistry() {
        // Pre-audit this static was a closed-set anti-pattern (every
        // new source had to be appended here in parallel with the
        // composition root). Post-audit production callers all derive
        // the prefix list from `Search.SourceLookup.allIDs` (via the
        // CupertinoComposition registry); the foundation-tier static
        // remains as a documentation/sanity list. This test pins the
        // invariant: if you register a new source in
        // `Cupertino.CompositionRoot.swift` but forget to append to
        // `Shared.Constants.SourcePrefix.allPrefixes`, the test fails
        // and CI catches the drift.
        let registeredIDs = Set(
            CupertinoComposition
                .makeProductionSourceRegistry()
                .allEnabled
                .map(\.definition.id)
        )
        let allPrefixes = Set(Shared.Constants.SourcePrefix.allPrefixes)
        let missingFromStatic = registeredIDs.subtracting(allPrefixes)
        let extraInStatic = allPrefixes.subtracting(registeredIDs)
        #expect(
            missingFromStatic.isEmpty,
            "Shared.Constants.SourcePrefix.allPrefixes is missing registered source(s): \(missingFromStatic.sorted()). Append them to allPrefixes (Shared.Constants.swift) or remove them from CupertinoComposition."
        )
        // `extraInStatic` allowed for special tokens + aliases:
        //   - `"all"` is the fan-out alias (not a real source)
        //   - `appleSampleCode` is the legacy alias for `samples`
        let allowedExtras: Set<String> = [
            "all",
            Shared.Constants.SourcePrefix.appleSampleCode,
        ]
        let unexpectedExtras = extraInStatic.subtracting(allowedExtras)
        #expect(
            unexpectedExtras.isEmpty,
            "Shared.Constants.SourcePrefix.allPrefixes has stale entries: \(unexpectedExtras.sorted()) — remove or add corresponding sources to CupertinoComposition."
        )
    }

    @Test("Open-set seam (post-#1042 Cluster 9): Search.FetchInfo.DefaultOutputDirKey is a rawValue-String struct; arbitrary keys resolve via Shared.Paths.directory(named:)")
    func openSetDefaultOutputDirKey() {
        // Post-Cluster-9 the closed enum became a RawRepresentable
        // struct. A new source declares `static let mySourceDir =
        // Self(rawValue: "my-source")` (or just constructs one at
        // call-time); resolveDirectory delegates to
        // paths.directory(named: key.rawValue). No more enum case +
        // switch arm + per-source Shared.Paths accessor.
        let custom = Search.FetchInfo.DefaultOutputDirKey(rawValue: "wwdc-transcripts")
        #expect(custom.rawValue == "wwdc-transcripts")
        // The 8 shipped keys still exist as static lets for
        // discoverability + back-compat.
        #expect(Search.FetchInfo.DefaultOutputDirKey.allKnownCases.count == 8)
        #expect(Search.FetchInfo.DefaultOutputDirKey.allKnownCases.contains(.docs))
    }
}
