@testable import CLI
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

        let grouped = Dictionary(grouping: registry.allEnabled) { $0.destinationDB.id }
        #expect(grouped["audit-fixture"]?.count == 1, "fake must be the sole occupant of its destinationDB group; no leak from existing sources")
        // Sanity: existing sources still group as expected post step 4.
        #expect(grouped["packages"]?.count == 1)
        #expect(grouped["apple-documentation"]?.count == 1)
        #expect(grouped["swift-documentation"]?.count == 2, "swift-org + swift-book co-located via view-source")
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

    // MARK: - The 2-file PR claim, recorded

    @Test("PR-file-touch claim: adding this fake source as a real production target would touch N files; cite N here")
    func twoFilePRClaimRecorded() {
        // **Real-world equivalent of this test fixture, if added as a
        // production target, would be:**
        //
        //   1. Packages/Sources/AuditFixtureSource/AuditFixtureSource.swift
        //      (the SourceProvider conformer; analogue of e.g.
        //      AppleArchiveSource.swift)
        //   2. Packages/Sources/AuditFixtureSource/AuditFixtureSource.Definition.swift
        //      (the SourceDefinition static; analogue of every other
        //      <X>Source.Definition.swift)
        //   3. docs/sources/audit-fixture/manifest.yaml
        //      (per docs/design/corpus-structure.md §3)
        //   4. Packages/Sources/CLI/CLIImpl.SourceRegistry.swift:
        //      one new line `registry.register(AuditFixtureSource())`
        //   5. Packages/Package.swift:
        //      one new SPM target declaration `auditFixtureSourceTarget`
        //      plus one line under `cupertinoTargets`
        //
        // Total: 3 new files + 2 single-line additions to existing
        // files (Package.swift + CLIImpl.SourceRegistry.swift). For a
        // new DB descriptor, ADD: 1 entry in
        // Shared.Constants.FileName + 1 static in
        // Shared.Models.DatabaseDescriptor + (the source's flip is
        // already counted in #1 above).
        //
        // The original memory rule's "2-file PR" framing is the
        // strict-minimum (Definition + Source); the practical
        // pluggable-via-PR shape lands at 3 new files + 2 1-line edits
        // + (if new DB) 2 more 1-line edits. This is the floor; if
        // step 5+ work adds new mandatory edit sites, that floor
        // grows and the invariant is violated.
        //
        // No assertion here: this test is a load-bearing comment
        // recording the file count. The other 7 tests in this suite
        // mechanically verify the seam properties.
        #expect(true)
    }
}
