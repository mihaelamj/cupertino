import Foundation
import IndexerModels
import SampleIndexModels
import SharedConstants

// MARK: - Indexer.SamplesService — concrete `run` orchestrator
//
// The value types (`Request`, `Outcome`, `Event`, `Phase`,
// `ServiceError`) plus the `Indexer.SamplesService.EventObserving`
// Observer protocol live in the foundation-only `IndexerModels` seam
// target. This file extends the same `Indexer.SamplesService` namespace
// to add the actual orchestrator behaviour.

extension Indexer.SamplesService {
    /// Build `samples.db` from extracted sample-code zips at
    /// `~/.cupertino/sample-code/`. Wraps an injected
    /// `Sample.Index.SamplesIndexingRunner` conformer with
    /// event-emission so this target doesn't import `SampleIndex` or
    /// `CoreSampleCode` directly — the CLI composition root supplies a
    /// `LiveSamplesIndexingRunner` backed by `Sample.Index.Database` +
    /// `Sample.Index.Builder` + `Sample.Core.Catalog`.
    public static func run(
        _ request: Request,
        samplesIndexingRunner: any Sample.Index.SamplesIndexingRunner,
        events: any EventObserving
    ) async throws -> Outcome {
        events.observe(event: .starting(
            sampleCodeDir: request.sampleCodeDir,
            samplesDB: request.samplesDB
        ))

        guard FileManager.default.fileExists(atPath: request.sampleCodeDir.path) else {
            throw ServiceError.sampleCodeDirectoryNotFound(request.sampleCodeDir)
        }

        // Drop the existing DB for a clean re-index. Matches the
        // search.db / packages.db pattern.
        if FileManager.default.fileExists(atPath: request.samplesDB.path) {
            events.observe(event: .removingExistingDB(request.samplesDB))
            try FileManager.default.removeItem(at: request.samplesDB)
        }

        let input = Sample.Index.SamplesIndexingInput(
            sampleCodeDir: request.sampleCodeDir,
            samplesDB: request.samplesDB,
            clear: request.clear,
            force: request.force
        )

        let observer = EventsToPhaseObserver(events: events)
        let result = try await samplesIndexingRunner.run(input: input, phaseObserver: observer)

        let outcome = Outcome(
            samplesDBPath: request.samplesDB,
            projectsIndexedThisRun: result.projectsIndexedThisRun,
            projectsTotal: result.projectsTotal,
            filesTotal: result.filesTotal,
            symbolsTotal: result.symbolsTotal,
            importsTotal: result.importsTotal,
            durationSeconds: result.durationSeconds
        )
        events.observe(event: .finished(outcome))
        return outcome
    }

    /// Adapter bridging the typed `Indexer.SamplesService.EventObserving`
    /// Observer protocol (from `IndexerModels`) to the typed
    /// `Sample.Index.SamplesIndexingPhaseObserving` Observer protocol that
    /// `Sample.Index.SamplesIndexingRunner.run` requires. Pure
    /// protocol-to-protocol adapter — no closures involved.
    private struct EventsToPhaseObserver: Sample.Index.SamplesIndexingPhaseObserving {
        let events: any EventObserving

        func observe(phase: Sample.Index.SamplesIndexingPhase) {
            switch phase {
            case .clearingExistingIndex:
                events.observe(event: .clearingExistingIndex)
            case .existingIndexNotice(let projects, let files):
                events.observe(event: .existingIndexNotice(projects: projects, files: files))
            case .loadingCatalog:
                events.observe(event: .loadingCatalog)
            case .catalogLoaded(let entryCount):
                events.observe(event: .catalogLoaded(entryCount: entryCount))
            case .indexingStart:
                events.observe(event: .indexingStart)
            case .projectProgress(let name, let percent, let p):
                let mapped: Event.Phase
                switch p {
                case .extracting: mapped = .extracting
                case .indexingFiles: mapped = .indexingFiles
                case .completed: mapped = .completed
                case .failed: mapped = .failed
                }
                events.observe(event: .projectProgress(name: name, percent: percent, phase: mapped))
            }
        }
    }
}
