import Foundation
import IndexerModels
import SearchModels
import SharedConstants

// MARK: - Indexer.DocsService — concrete `run` orchestrator
//
// The value types (`Request`, `Outcome`, `Event`) plus the
// `Indexer.DocsService.EventObserving` Observer protocol live in the
// foundation-only `IndexerModels` seam target. This file extends the
// same `Indexer.DocsService` namespace to add the actual orchestrator
// behaviour.

extension Indexer.DocsService {
    /// Build `search.db` from on-disk corpus (apple-docs JSON, swift
    /// evolution markdown, swift.org, archive, HIG). Wraps an injected
    /// `Search.DocsIndexingRunner` conformer with event-emission so
    /// this target doesn't import `Search` directly — the CLI
    /// composition root supplies a `LiveDocsIndexingRunner` backed by
    /// `Search.Index` + `Search.IndexBuilder`.
    public static func run(
        _ request: Request,
        markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
        sampleCatalogProvider: any Search.SampleCatalogProvider,
        docsIndexingRunner: any Search.DocsIndexingRunner,
        events: any EventObserving
    ) async throws -> Outcome {
        let docsURL = request.docsDir
            ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.docs)
        let evolutionURL = request.evolutionDir
            ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.swiftEvolution)
        let swiftOrgURL = request.swiftOrgDir
            ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.swiftOrg)
        let archiveURL = request.archiveDir
            ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.archive)
        let higURL = request.higDir
            ?? request.baseDir.appendingPathComponent(Shared.Constants.Directory.hig)
        let searchDBURL = request.searchDB
            ?? request.baseDir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)

        // FTS5 doesn't tolerate INSERT OR REPLACE cleanly; fresh DB
        // every time keeps the correctness story simple.
        if FileManager.default.fileExists(atPath: searchDBURL.path) {
            events.observe(event: .removingExistingDB(searchDBURL))
            try FileManager.default.removeItem(at: searchDBURL)
        }

        events.observe(event: .initializingIndex)

        let evolutionDirToUse = optionalDir(evolutionURL, label: "Swift Evolution", events: events)
        let swiftOrgDirToUse = optionalDir(swiftOrgURL, label: "Swift.org", events: events)
        let archiveDirToUse = optionalDir(archiveURL, label: "Apple Archive", events: events)
        let higDirToUse = optionalDir(higURL, label: "HIG", events: events)

        if !Indexer.Preflight.checkDocsHaveAvailability(docsDir: docsURL) {
            events.observe(event: .availabilityMissing)
        }

        let input = Search.DocsIndexingInput(
            searchDBPath: searchDBURL,
            docsDirectory: docsURL,
            evolutionDirectory: evolutionDirToUse,
            swiftOrgDirectory: swiftOrgDirToUse,
            archiveDirectory: archiveDirToUse,
            higDirectory: higDirToUse,
            clearExisting: request.clear,
            markdownStrategy: markdownStrategy,
            sampleCatalogProvider: sampleCatalogProvider
        )

        let reporter = EventsToProgressReporter(events: events)
        let result = try await docsIndexingRunner.run(input: input, progress: reporter)

        let outcome = Outcome(
            searchDBPath: searchDBURL,
            documentCount: result.documentCount,
            frameworkCount: result.frameworkCount
        )
        events.observe(event: .finished(outcome))
        return outcome
    }

    private static func optionalDir(
        _ url: URL,
        label: String,
        events: any EventObserving
    ) -> URL? {
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        events.observe(event: .missingOptionalSource(label: label, url: url))
        return nil
    }

    /// Adapter bridging the typed `Indexer.DocsService.EventObserving`
    /// Observer protocol (from `IndexerModels`) to the typed
    /// `Search.IndexingProgressReporting` Observer protocol that
    /// `Search.DocsIndexingRunner.run` requires. Both sides are Observer
    /// protocols, so this is a pure protocol-to-protocol adapter — no
    /// closures involved.
    private struct EventsToProgressReporter: Search.IndexingProgressReporting {
        let events: any EventObserving

        func report(processed: Int, total: Int) {
            let percent = Double(processed) / Double(total) * 100
            events.observe(event: .progress(processed: processed, total: total, percent: percent))
        }
    }
}
