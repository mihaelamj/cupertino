import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - Search.SourceRegistry.groupedByDestinationDB(excluding:) pin tests

//
// Step 5 of the per-source DB split epic
// (`docs/design/per-source-db-split.md`): the composition root needs
// to group providers by destinationDB so the indexer dispatch can
// open one DB per group and fan out writes. This helper is the
// foundation-tier seam that the CLI-side dispatcher consumes.

@Suite("Search.SourceRegistry.groupedByDestinationDB")
struct SourceRegistryGroupingTests {
    // MARK: - Test-local fake providers

    /// Minimal provider conformer for the grouping helper test. Only
    /// the fields the helper inspects (destinationDB, definition.id) are
    /// populated meaningfully; the rest are sentinels.
    private struct FakeProvider: Search.SourceProvider {
        let id: String
        let dbDescriptor: Shared.Models.DatabaseDescriptor

        var definition: Search.SourceDefinition {
            Search.SourceDefinition(
                id: id,
                displayName: id,
                emoji: "🔧",
                properties: Search.SourceProperties(
                    authority: 0.5, freshness: 0.5, comprehensiveness: 0.5,
                    codeExamples: 0.0, hasAvailability: 0.0,
                    designFocus: 0.0, languageFocus: 0.0, searchQuality: 0.5
                ),
                intents: [.apiReference]
            )
        }

        var fetchInfo: Search.FetchInfo? {
            nil
        }

        var destinationDB: Shared.Models.DatabaseDescriptor {
            dbDescriptor
        }

        var capabilities: Search.Capabilities {
            .empty
        }

        func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
            FakeStrategy(source: id)
        }

        func makeIndexer() -> any Search.SourceIndexer {
            FakeIndexer(sourceID: id)
        }
    }

    private struct FakeStrategy: Search.SourceIndexingStrategy {
        let source: String

        func indexItems(
            into _: any Search.Database & Search.IndexWriter,
            progress _: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats {
            Search.IndexStats(source: source, indexed: 0, skipped: 0, wasSkipped: true, skipReason: "fake")
        }
    }

    private struct FakeIndexer: Search.SourceIndexer {
        let sourceID: String
        var displayName: String {
            sourceID
        }

        func extractCode(
            documentID _: Int,
            content _: String,
            uri _: String,
            defaultFramework _: String?
        ) -> Search.ExtractedContent? {
            nil
        }
    }

    // MARK: - Tests

    @Test("Empty registry returns empty grouping")
    func emptyRegistryReturnsEmpty() {
        let registry = Search.SourceRegistry()
        #expect(registry.groupedByDestinationDB().isEmpty)
    }

    @Test("Single-source registry yields one group containing one provider")
    func singleSourceOneGroup() {
        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "foo", dbDescriptor: .search))
        let grouped = registry.groupedByDestinationDB()
        #expect(grouped.count == 1)
        #expect(grouped[.search]?.count == 1)
        #expect(grouped[.search]?.first?.definition.id == "foo")
    }

    @Test("Multiple sources sharing a destinationDB are co-located in one group (view-source pattern)")
    func sharedDestinationCoLocates() {
        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "swift-org-fake", dbDescriptor: .swiftDocumentation))
        registry.register(FakeProvider(id: "swift-book-fake", dbDescriptor: .swiftDocumentation))
        registry.register(FakeProvider(id: "hig-fake", dbDescriptor: .hig))

        let grouped = registry.groupedByDestinationDB()
        #expect(grouped.count == 2, "2 distinct destinationDBs (swift-documentation, hig)")
        #expect(grouped[.swiftDocumentation]?.count == 2, "swift-org + swift-book co-located")
        #expect(grouped[.hig]?.count == 1)
    }

    @Test("excluding: set filters out the named descriptors entirely")
    func excludingFiltersDescriptors() {
        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "apple-docs-fake", dbDescriptor: .appleDocumentation))
        registry.register(FakeProvider(id: "packages-fake", dbDescriptor: .packages))
        registry.register(FakeProvider(id: "hig-fake", dbDescriptor: .hig))

        let grouped = registry.groupedByDestinationDB(excluding: [.packages])
        #expect(grouped.count == 2)
        #expect(grouped[.packages] == nil, "packages was excluded; must not appear")
        #expect(grouped[.appleDocumentation]?.count == 1)
        #expect(grouped[.hig]?.count == 1)
    }

    @Test("Disabled providers are NOT in the grouping (helper consults .allEnabled)")
    func disabledProvidersFilteredOut() {
        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "enabled-fake", dbDescriptor: .hig))
        registry.register(FakeProvider(id: "disabled-fake", dbDescriptor: .hig))
        registry.setEnabled(false, forSourceID: "disabled-fake")

        let grouped = registry.groupedByDestinationDB()
        #expect(grouped[.hig]?.count == 1, "only the enabled fake should be in the group")
        #expect(grouped[.hig]?.first?.definition.id == "enabled-fake")
    }

    @Test("Keying by full DatabaseDescriptor (not just id) protects against id-collision regressions")
    func fullDescriptorKeyingProtectsAgainstCollisions() {
        // Two synthetic descriptors with the SAME `id` but different
        // `filename` would NOT collide here (they hash differently as
        // values). If a future regression accidentally introduces such
        // a pair, this test pins that the grouping helper partitions
        // them as two distinct groups, not one conflated bucket.
        let descA = Shared.Models.DatabaseDescriptor(id: "collide", filename: "a.db", displayName: "A")
        let descB = Shared.Models.DatabaseDescriptor(id: "collide", filename: "b.db", displayName: "B")
        #expect(descA != descB, "descriptors with same id but different filename must be distinct values")

        var registry = Search.SourceRegistry()
        registry.register(FakeProvider(id: "src-a", dbDescriptor: descA))
        registry.register(FakeProvider(id: "src-b", dbDescriptor: descB))
        let grouped = registry.groupedByDestinationDB()
        #expect(grouped.count == 2, "two distinct descriptors must produce two groups, not one")
    }

    @Test("Production registry: groupedByDestinationDB(excluding: [.packages]) reproduces step-5 dispatcher input")
    func productionRegistryStepFiveShape() {
        // This is the shape the step-5 dispatcher will consume. Pinning
        // the expected groups so a future provider-registration order
        // change doesn't silently move sources between groups.
        // SwiftOrgSource + SwiftBookSource share .swiftDocumentation
        // (view-source pattern); every other source has its own group;
        // .packages is excluded (PackagesSource pipes through
        // Indexer.PackagesService outside Search.IndexBuilder).
        var registry = Search.SourceRegistry()
        // Synthesize the post-step-4 production shape by registering
        // FakeProvider instances with the same destinationDB values
        // each real source declares today.
        registry.register(FakeProvider(id: "apple-docs", dbDescriptor: .appleDocumentation))
        registry.register(FakeProvider(id: "hig", dbDescriptor: .hig))
        registry.register(FakeProvider(id: "samples", dbDescriptor: .search))
        registry.register(FakeProvider(id: "apple-archive", dbDescriptor: .appleArchive))
        registry.register(FakeProvider(id: "swift-evolution", dbDescriptor: .swiftEvolution))
        registry.register(FakeProvider(id: "swift-org", dbDescriptor: .swiftDocumentation))
        registry.register(FakeProvider(id: "swift-book", dbDescriptor: .swiftDocumentation))
        registry.register(FakeProvider(id: "packages", dbDescriptor: .packages))

        let grouped = registry.groupedByDestinationDB(excluding: [.packages])
        #expect(grouped.count == 6, "6 search-style destination DBs after excluding packages")
        #expect(grouped[.appleDocumentation]?.count == 1)
        #expect(grouped[.hig]?.count == 1)
        #expect(grouped[.search]?.count == 1, "SampleCodeSource analogue still at .search until step 6")
        #expect(grouped[.appleArchive]?.count == 1)
        #expect(grouped[.swiftEvolution]?.count == 1)
        #expect(grouped[.swiftDocumentation]?.count == 2, "swift-org + swift-book co-located")
        #expect(grouped[.packages] == nil, "explicitly excluded")
    }
}
