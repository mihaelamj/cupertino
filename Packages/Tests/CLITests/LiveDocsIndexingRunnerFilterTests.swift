@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - LiveDocsIndexingRunner per-source dispatch filter tests

/// Tests the per-source-id filter on `LiveDocsIndexingRunner` that
/// closes the round-7/8 critic findings #4/#5/#7/#9/#10: pre-fix
/// `--source apple-docs` triggered the full docs runner (building
/// every docs-bucket DB whose corpus was on disk); post-fix the
/// runner narrows to only the destinations whose providers match the
/// selected source-ids. View-source co-location is preserved
/// (`--source swift-org` keeps swift-book in the same group per the
/// 2026-05-25 user directive).
///
/// We don't construct the full Indexer.DocsService pipeline here
/// (that needs source directories with content); instead we mirror
/// the filter logic against the production registry shape and pin
/// the expected destination-DB sets for each `--source <id>`
/// selection. The actual filter code lives in
/// `LiveDocsIndexingRunner.run` and is exercised by the integration
/// suite (`Issue1037OneDBIntegrationTests`); the assertions here
/// pin the contract per source.
@Suite("LiveDocsIndexingRunner per-source dispatch filter")
struct LiveDocsIndexingRunnerFilterTests {
    /// Mirror of the filter logic in `LiveDocsIndexingRunner.run`,
    /// extracted so the test can pin the contract without spinning up
    /// the full DocsService pipeline. If this drifts from the production
    /// code, `Issue1037OneDBIntegrationTests` catches it end-to-end.
    private func filterGroups(
        selectedSourceIDs: Set<String>?
    ) -> Set<String> {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let allGroups = registry.groupedByDestinationDB(excluding: [.packages])
        let filtered: [Shared.Models.DatabaseDescriptor: [any Search.SourceProvider]]
        if let selectedSourceIDs {
            filtered = allGroups.filter { _, providers in
                providers.contains { provider in
                    selectedSourceIDs.contains(provider.definition.id)
                }
            }
        } else {
            filtered = allGroups
        }
        return Set(filtered.keys.map(\.id))
    }

    // MARK: - Per-source dispatch

    @Test("nil selectedSourceIDs builds every docs-bucket destination (pre-#1037 bucket-level default)")
    func nilFilterBuildsAll() {
        let destinations = filterGroups(selectedSourceIDs: nil)
        // Post #1038, swift-org and swift-book are separate
        // destinations (no more view-source co-location).
        #expect(destinations == [
            "apple-archive",
            "apple-documentation",
            "apple-sample-code",
            "hig",
            "swift-book",
            "swift-evolution",
            "swift-org",
        ])
    }

    @Test("--source apple-docs narrows to apple-documentation.db only")
    func appleDocsOnly() {
        let destinations = filterGroups(selectedSourceIDs: [Shared.Constants.SourcePrefix.appleDocs])
        #expect(destinations == ["apple-documentation"])
    }

    @Test("--source hig narrows to hig.db only")
    func higOnly() {
        let destinations = filterGroups(selectedSourceIDs: [Shared.Constants.SourcePrefix.hig])
        #expect(destinations == ["hig"])
    }

    @Test("--source swift-evolution narrows to swift-evolution.db only")
    func swiftEvolutionOnly() {
        let destinations = filterGroups(selectedSourceIDs: [Shared.Constants.SourcePrefix.swiftEvolution])
        #expect(destinations == ["swift-evolution"])
    }

    @Test("--source apple-archive narrows to apple-archive.db only")
    func appleArchiveOnly() {
        let destinations = filterGroups(selectedSourceIDs: [Shared.Constants.SourcePrefix.appleArchive])
        #expect(destinations == ["apple-archive"])
    }

    @Test("--source samples narrows to apple-sample-code.db only (SampleCodeSource group)")
    func samplesOnly() {
        // Samples FTS rows in the docs runner live in
        // .appleSampleCode (one-DB-two-tracks per #1037). Rich
        // schema is built by the standalone Sample.Index pipeline
        // outside the docs runner.
        let destinations = filterGroups(selectedSourceIDs: [Shared.Constants.SourcePrefix.samples])
        #expect(destinations == ["apple-sample-code"])
    }

    // MARK: - Swift-org / Swift-Book separation (#1038)

    @Test("--source swift-org narrows to swift-org.db only (no longer pulls swift-book)")
    func swiftOrgAlone() {
        // Pre-#1038 view-source: --source swift-org pulled swift-book
        // because they shared swift-documentation.db. Post-#1038
        // ("diff db for each source"), each has its own DB.
        // SwiftOrgStrategy walks the shared corpus directory but its
        // per-page emission is filtered to `.swiftOrgOnly` via the
        // shared crawl helper; swift-book pages land in swift-book.db
        // via SwiftBookStrategy's separate invocation.
        let destinations = filterGroups(selectedSourceIDs: [Shared.Constants.SourcePrefix.swiftOrg])
        #expect(destinations == ["swift-org"])
    }

    @Test("--source swift-book narrows to swift-book.db only (no longer pulls swift-org)")
    func swiftBookAlone() {
        let destinations = filterGroups(selectedSourceIDs: [Shared.Constants.SourcePrefix.swiftBook])
        #expect(destinations == ["swift-book"])
    }

    @Test("--source swift-org AND --source swift-book builds BOTH destinations (post #1038 each owns its own DB)")
    func swiftOrgAndSwiftBookBothGroups() {
        let destinations = filterGroups(selectedSourceIDs: [
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ])
        #expect(destinations == ["swift-org", "swift-book"])
    }

    // MARK: - Multi-source

    @Test("Multiple --source values build the union of their destinations")
    func multipleSourcesUnion() {
        let destinations = filterGroups(selectedSourceIDs: [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
        ])
        #expect(destinations == ["apple-documentation", "hig", "swift-evolution"])
    }

    @Test("--source covering every docs-bucket source matches the nil-filter set")
    func everyDocsSourceMatchesNilFilter() {
        let allDocsBucketIDs: Set<String> = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.samples,
        ]
        let filtered = filterGroups(selectedSourceIDs: allDocsBucketIDs)
        let unfiltered = filterGroups(selectedSourceIDs: nil)
        #expect(filtered == unfiltered)
    }

    // MARK: - Edge cases

    @Test("Empty selectedSourceIDs yields no destinations (no group to build)")
    func emptySetYieldsNoDestinations() {
        let destinations = filterGroups(selectedSourceIDs: [])
        #expect(destinations.isEmpty)
    }

    @Test("--source packages is filtered out by `excluding: [.packages]`, so even passing it yields no docs-bucket destinations")
    func packagesNotInDocsRunner() {
        // packages source's destinationDB is `.packages`, which the
        // docs runner explicitly excludes (its write pipeline is the
        // standalone PackagesService). Filtering on `packages` therefore
        // produces an empty destination set in the docs runner.
        let destinations = filterGroups(selectedSourceIDs: [Shared.Constants.SourcePrefix.packages])
        #expect(destinations.isEmpty)
    }

    @Test("Unknown source-id is silently dropped (no destination contributes)")
    func unknownSourceIDSilent() {
        let destinations = filterGroups(selectedSourceIDs: ["not-a-real-source"])
        #expect(destinations.isEmpty)
    }
}
