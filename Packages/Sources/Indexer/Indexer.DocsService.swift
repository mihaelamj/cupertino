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

        // Surface the resolved output path upfront so long-running save
        // jobs make their destination visible without the user having
        // to re-derive base-dir + filename composition from CLI args.
        // Fires before any disk activity.
        events.observe(event: .databaseTarget(searchDBURL))

        // FTS5 doesn't tolerate INSERT OR REPLACE cleanly; fresh DB
        // every time keeps the correctness story simple.
        if FileManager.default.fileExists(atPath: searchDBURL.path) {
            events.observe(event: .removingExistingDB(searchDBURL))
            try FileManager.default.removeItem(at: searchDBURL)
        }

        events.observe(event: .initializingIndex)

        // #1059: gate optional-dir probes by `selectedSourceIDs` so a
        // single-source save (e.g. `cupertino save --source apple-docs`)
        // doesn't spam `ℹ️  <X> directory not found…` info lines for
        // every OTHER docs-tier source. Pre-fix the 4 calls below
        // fired unconditionally. Post-fix `nil` selection (legacy
        // callers + `--all`) keeps the original full-fan-out probe;
        // an explicit selection narrows to just the sources the user
        // asked for. The optional dirs the strategy receives stay
        // `nil` for sources out of scope, which the strategy already
        // tolerates (its own scope filter drops them).
        func probeIfSelected(_ url: URL, sourceID: String, label: String) -> URL? {
            if let selected = request.selectedSourceIDs, !selected.contains(sourceID) {
                return nil
            }
            return optionalDir(url, label: label, events: events)
        }
        let evolutionDirToUse = probeIfSelected(
            evolutionURL,
            sourceID: Shared.Constants.SourcePrefix.swiftEvolution,
            label: "Swift Evolution"
        )
        let swiftOrgDirToUse = probeIfSelected(
            swiftOrgURL,
            sourceID: Shared.Constants.SourcePrefix.swiftOrg,
            label: "Swift.org"
        )
        let archiveDirToUse = probeIfSelected(
            archiveURL,
            sourceID: Shared.Constants.SourcePrefix.appleArchive,
            label: "Apple Archive"
        )
        let higDirToUse = probeIfSelected(
            higURL,
            sourceID: Shared.Constants.SourcePrefix.hig,
            label: "HIG"
        )

        if !Indexer.Preflight.checkDocsHaveAvailability(docsDir: docsURL) {
            events.observe(event: .availabilityMissing)
        }

        // #1045 Gap 4: thread the registry-derived per-source dir map
        // through to the indexer Input so the dispatcher's
        // resolveSourceDirectory can route arbitrary new sources by
        // their definition.id without a typed-field-or-switch-arm edit.
        let input = Search.DocsIndexingInput(
            searchDBPath: searchDBURL,
            docsDirectory: docsURL,
            evolutionDirectory: evolutionDirToUse,
            swiftOrgDirectory: swiftOrgDirToUse,
            archiveDirectory: archiveDirToUse,
            higDirectory: higDirToUse,
            clearExisting: request.clear,
            markdownStrategy: markdownStrategy,
            sampleCatalogProvider: sampleCatalogProvider,
            directoryByKey: request.directoryByKey
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
            // Symmetric with the miss path: emit a positive event so
            // long-running save jobs surface upfront which optional
            // sources will be indexed. Pre-fix the success path was
            // silent, leaving the user without a "yes, this source is
            // queued" signal until the per-source strategy actually
            // started running (potentially hours into an 11h job).
            events.observe(event: .foundOptionalSource(label: label, url: url))
            // #779 fix: resolve symlinks before handing the URL to the strategies.
            // FileManager.contentsOfDirectory(at:) (URL variant) does NOT follow
            // a leaf directory-symlink; it operates on the symlink inode itself
            // and the kernel returns ENOTDIR (POSIX 20), which Foundation wraps
            // as NSCocoaErrorDomain 256 with the bare "couldn't be opened"
            // string. resolvingSymlinksInPath() is a no-op on non-symlink URLs,
            // so this is safe for the brew layout (no symlinks under
            // ~/.cupertino/) and fixes the dev layout (symlinks in
            // ~/.cupertino-dev/{swift-evolution,swift-org,archive,hig}).
            return url.resolvingSymlinksInPath()
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
