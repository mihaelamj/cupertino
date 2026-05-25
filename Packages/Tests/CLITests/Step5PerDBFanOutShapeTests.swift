@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - Step 5b shape pin tests

//
// Step 5b of `docs/design/per-source-db-split.md` refactored
// `CLIImpl.Command.Save.LiveDocsIndexingRunner.run(...)` from a
// single-search.db write path to a per-DB fan-out via
// `Search.SourceRegistry.groupedByDestinationDB(excluding: [.packages])`.
// This suite pins the dispatcher's input shape so a future provider
// registration change can't silently re-route writes.
//
// Note: this suite does NOT execute an end-to-end save (that needs the
// full CLI harness + fixture corpus, covered by Issue1033 + the
// query-batteries smoke). It pins the GROUPING the dispatcher
// consumes; the production execution sits on top of this grouping
// + per-DB Search.Index instantiation.

@Suite("Step 5b: production registry grouping shape (the dispatcher's input)")
struct Step5PerDBFanOutShapeTests {
    @Test("Production registry groupedByDestinationDB(excluding: [.packages]) yields the expected 7 groups")
    func productionGroupingShape() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let groups = registry.groupedByDestinationDB(excluding: [.packages])
        // Post #1038 ("diff db for each source"), swift-org and
        // swift-book each own their own DB; the 7 search-style
        // sources fan out into 7 distinct destinationDBs.
        // SampleCodeSource still lives at .appleSampleCode (one DB
        // shared with the Sample.Index.Builder rich-schema pipeline;
        // two table tracks in one file per #1037).
        #expect(groups.count == 7, "expected 7 groups; got \(groups.count): \(groups.keys.map(\.id).sorted())")
        #expect(groups[.appleDocumentation]?.count == 1, "AppleDocsSource alone")
        #expect(groups[.hig]?.count == 1, "HIGSource alone")
        #expect(groups[.appleArchive]?.count == 1, "AppleArchiveSource alone")
        #expect(groups[.swiftEvolution]?.count == 1, "SwiftEvolutionSource alone")
        #expect(groups[.swiftOrg]?.count == 1, "SwiftOrgSource alone post #1038 (was co-located with swift-book)")
        #expect(groups[.swiftBook]?.count == 1, "SwiftBookSource alone post #1038 (was view-source under swiftDocumentation)")
        #expect(
            groups[.appleSampleCode]?.count == 1,
            "SampleCodeSource at .appleSampleCode (sharing samples.db with Sample.Index.Builder)"
        )
        #expect(groups[.swiftDocumentation] == nil, "post #1038 no provider targets the legacy .swiftDocumentation descriptor")
        #expect(groups[.search] == nil, "post step-7a flip, no provider is at .search")
        #expect(groups[.packages] == nil, "PackagesSource is filtered out by excluding: [.packages]")
    }

    @Test("Production grouping sorted by descriptor.id gives a deterministic build order")
    func productionGroupingOrder() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let groups = registry.groupedByDestinationDB(excluding: [.packages])
        let order = groups.sorted { $0.key.id < $1.key.id }.map(\.key.id)
        #expect(order == [
            "apple-archive",
            "apple-documentation",
            "apple-sample-code",
            "hig",
            "swift-book",
            "swift-evolution",
            "swift-org",
        ], "alphabetical-by-id order makes the per-DB fan-out reproducible across runs")
    }

    @Test("Each group's providers' source-ids match the descriptor they declared")
    func groupContentsMatchSourceDeclarations() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let groups = registry.groupedByDestinationDB(excluding: [.packages])

        let appleDocs = groups[.appleDocumentation]?.map(\.definition.id) ?? []
        #expect(appleDocs == ["apple-docs"], "got: \(appleDocs)")

        let hig = groups[.hig]?.map(\.definition.id) ?? []
        #expect(hig == ["hig"])

        let archive = groups[.appleArchive]?.map(\.definition.id) ?? []
        #expect(archive == ["apple-archive"])

        let evolution = groups[.swiftEvolution]?.map(\.definition.id) ?? []
        #expect(evolution == ["swift-evolution"])

        // Post #1038: each sub-source owns its own group.
        let swiftOrg = groups[.swiftOrg]?.map(\.definition.id) ?? []
        #expect(swiftOrg == ["swift-org"])

        let swiftBook = groups[.swiftBook]?.map(\.definition.id) ?? []
        #expect(swiftBook == ["swift-book"])

        let samples = groups[.appleSampleCode]?.map(\.definition.id) ?? []
        #expect(samples == ["samples"], "SampleCodeSource (definition.id 'samples') alone at .appleSampleCode (one-DB collapse)")
    }

    @Test("Per-DB output paths derived from the base directory + descriptor.filename")
    func perDBPathDerivation() {
        let baseDir = URL(fileURLWithPath: "/tmp/cupertino-test-base")
        // Mirror the path-derivation logic at LiveDocsIndexingRunner.run:
        // dbPath = baseDirectory.appendingPathComponent(descriptor.filename)
        let appleDocPath = baseDir.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleDocumentation.filename)
        let higPath = baseDir.appendingPathComponent(Shared.Models.DatabaseDescriptor.hig.filename)
        let evolutionPath = baseDir.appendingPathComponent(Shared.Models.DatabaseDescriptor.swiftEvolution.filename)
        #expect(appleDocPath.path == "/tmp/cupertino-test-base/apple-documentation.db")
        #expect(higPath.path == "/tmp/cupertino-test-base/hig.db")
        #expect(evolutionPath.path == "/tmp/cupertino-test-base/swift-evolution.db")
    }
}
