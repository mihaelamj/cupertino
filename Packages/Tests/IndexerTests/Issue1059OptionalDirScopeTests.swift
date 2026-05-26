import Foundation
@testable import Indexer
import IndexerModels
import SearchModels
import SharedConstants
import Testing

// MARK: - Issue 1059 contract: DocsService gates optional-dir probes by selection

//
// #1059: `cupertino save --source apple-docs` was spamming
// `ℹ️  <X> directory not found at …` info lines for the 4 other
// docs-tier sources (swift-evolution, swift-org, apple-archive, hig)
// even though those sources weren't in scope for the save.
//
// The fix: `Indexer.DocsService.Request.selectedSourceIDs: Set<String>?`
// gates the 4 `optionalDir(...)` probes in `DocsService.run`. Nil keeps
// the original full-fan-out behaviour (legacy callers + `--all`). A
// non-nil selection narrows the probes to just the sources in scope —
// each unselected source's directory isn't probed and no
// `missingOptionalSource` event is observed for it.
//
// This suite exercises the event-emission contract directly via a
// recording observer; no on-disk index is built.

private final class RecordingObserver: Indexer.DocsService.EventObserving, @unchecked Sendable {
    var events: [Indexer.DocsService.Event] = []

    func observe(event: Indexer.DocsService.Event) {
        events.append(event)
    }

    /// Convenience: every `missingOptionalSource` label emitted.
    var missingOptionalLabels: [String] {
        events.compactMap { event in
            if case let .missingOptionalSource(label, _) = event { return label }
            return nil
        }
    }

    /// Convenience: every `foundOptionalSource` label emitted.
    var foundOptionalLabels: [String] {
        events.compactMap { event in
            if case let .foundOptionalSource(label, _) = event { return label }
            return nil
        }
    }
}

/// Stub `Search.DocsIndexing.Runner` that immediately returns a zero
/// outcome — the test only exercises the pre-runner optional-dir
/// probe phase.
private struct StubDocsIndexingRunner: Search.DocsIndexing.Runner {
    func run(
        input _: Search.DocsIndexing.Input,
        progress _: any Search.IndexingProgressReporting
    ) async throws -> Search.DocsIndexing.Outcome {
        Search.DocsIndexing.Outcome(documentCount: 0, frameworkCount: 0)
    }
}

/// Stub markdown strategy — never invoked in this contract test path.
private struct StubMarkdownStrategy: Search.MarkdownToStructuredPageStrategy {
    func convert(markdown _: String, url _: URL?) -> Shared.Models.StructuredDocumentationPage? {
        nil
    }
}

/// Stub sample catalog — never invoked in this contract test path.
private struct StubSampleCatalogProvider: Search.SampleCatalogProvider {
    func fetch() async -> Search.SampleCatalog.State {
        .missing(onDiskPath: "/dev/null")
    }
}

@Suite("Issue 1059: DocsService.Request.selectedSourceIDs gates optional-dir probes")
struct Issue1059OptionalDirScopeTests {
    private func makeRequest(
        selectedSourceIDs: Set<String>?,
        baseDir: URL
    ) -> Indexer.DocsService.Request {
        // All 4 optional dirs point at non-existent paths so the probe,
        // when fired, would emit `missingOptionalSource`. The test
        // assertion is on which events DID vs DID NOT fire — never
        // about real disk content.
        let nonexistent = { (suffix: String) in
            baseDir.appendingPathComponent("nonexistent-\(suffix)")
        }
        return Indexer.DocsService.Request(
            baseDir: baseDir,
            docsDir: nonexistent("docs"),
            evolutionDir: nonexistent("evolution"),
            swiftOrgDir: nonexistent("swift-org"),
            archiveDir: nonexistent("archive"),
            higDir: nonexistent("hig"),
            searchDB: baseDir.appendingPathComponent("search.db"),
            clear: false,
            directoryByKey: [:],
            selectedSourceIDs: selectedSourceIDs
        )
    }

    private func runService(
        request: Indexer.DocsService.Request,
        observer: RecordingObserver
    ) async throws {
        _ = try await Indexer.DocsService.run(
            request,
            markdownStrategy: StubMarkdownStrategy(),
            sampleCatalogProvider: StubSampleCatalogProvider(),
            docsIndexingRunner: StubDocsIndexingRunner(),
            events: observer
        )
    }

    @Test("Nil selection keeps the legacy 4-probe fan-out (backward compat for --all + legacy callers)")
    func nilSelectionProbesAll() async throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-1059-nil-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let observer = RecordingObserver()
        try await runService(
            request: makeRequest(selectedSourceIDs: nil, baseDir: tempBase),
            observer: observer
        )

        // All 4 optional-source labels surface in the event stream.
        let missingLabels = Set(observer.missingOptionalLabels)
        #expect(missingLabels.contains("Swift Evolution"))
        #expect(missingLabels.contains("Swift.org"))
        #expect(missingLabels.contains("Apple Archive"))
        #expect(missingLabels.contains("HIG"))
    }

    @Test("Single-source selection silences the 3 other optional-dir probes (#1059 close)")
    func singleSourceSelectionSilencesOthers() async throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-1059-single-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let observer = RecordingObserver()
        try await runService(
            request: makeRequest(
                // User runs `cupertino save --source apple-docs`.
                // apple-docs is the bucket-tier source whose optional
                // dirs are the 4 other docs-tier siblings; none of
                // them are in scope for this save.
                selectedSourceIDs: ["apple-docs"],
                baseDir: tempBase
            ),
            observer: observer
        )

        // Pre-fix: all 4 labels would surface as `missingOptionalSource`
        // events even though the user only asked for apple-docs.
        // Post-fix: zero events for the 3 docs-tier siblings.
        #expect(
            observer.missingOptionalLabels.isEmpty,
            "Expected no missingOptionalSource events for sources outside the selection; got \(observer.missingOptionalLabels)"
        )
        #expect(observer.foundOptionalLabels.isEmpty)
    }

    @Test("Selection including swift-evolution probes only that source")
    func selectionNarrowsToSelectedOnly() async throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-1059-narrow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let observer = RecordingObserver()
        try await runService(
            request: makeRequest(
                selectedSourceIDs: ["swift-evolution"],
                baseDir: tempBase
            ),
            observer: observer
        )

        // Only the swift-evolution probe fires; the other 3 stay silent.
        #expect(observer.missingOptionalLabels == ["Swift Evolution"])
    }
}
