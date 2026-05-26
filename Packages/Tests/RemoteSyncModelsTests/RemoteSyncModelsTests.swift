import Foundation
import RemoteSyncModels
import Testing

// MARK: - RemoteSyncModels public surface smoke tests

//
// `RemoteSyncModels` is the foundation-only seam target for the
// `RemoteSync` producer. It owns:
// - the `RemoteSync` namespace anchor
// - the `RemoteSync.Progress` / `IndexState` / `IndexerResult` /
//   `IndexerError` value types
// - the `DocumentIndexing` Strategy + `IndexerProgressObserving` /
//   `IndexerDocumentObserving` Observer protocols
//
// Tests below pin the public surface so a rename or accidental
// deletion fails CI before downstream consumers discover it. The
// heavy behavioural tests for `IndexState` persistence live in
// `RemoteSyncTests`; this suite is scoped to the seam.

// MARK: - Namespace + constants

@Suite("RemoteSync namespace anchor + constants")
struct RemoteSyncNamespaceTests {
    @Test("RemoteSync namespace exposes package version + GitHub constants")
    func namespaceConstants() {
        #expect(!RemoteSync.version.isEmpty)
        #expect(RemoteSync.defaultRepository == "mihaelamj/cupertino-docs")
        #expect(RemoteSync.defaultBranch == "main")
        #expect(RemoteSync.rawGitHubBaseURL == "https://raw.githubusercontent.com")
        #expect(RemoteSync.gitHubAPIBaseURL == "https://api.github.com")
    }
}

// MARK: - Progress value type

@Suite("RemoteSync.Progress")
struct RemoteSyncProgressTests {
    @Test("Stores every field via init")
    func progressRoundTrip() {
        let progress = RemoteSync.Progress(
            phase: .docs,
            framework: "SwiftUI",
            frameworkIndex: 3,
            frameworksTotal: 10,
            fileIndex: 25,
            filesTotal: 100,
            elapsed: 12.5,
            overallProgress: 0.28
        )
        #expect(progress.phase == .docs)
        #expect(progress.framework == "SwiftUI")
        #expect(progress.frameworkIndex == 3)
        #expect(progress.frameworksTotal == 10)
        #expect(progress.fileIndex == 25)
        #expect(progress.filesTotal == 100)
        #expect(progress.elapsed == 12.5)
        #expect(progress.overallProgress == 0.28)
    }

    @Test("estimatedTimeRemaining returns nil for near-zero progress")
    func progressNoETAEarly() {
        let progress = RemoteSync.Progress(
            phase: .docs,
            framework: nil,
            frameworkIndex: 0,
            frameworksTotal: 100,
            fileIndex: 0,
            filesTotal: 0,
            elapsed: 0.5,
            overallProgress: 0.001
        )
        #expect(progress.estimatedTimeRemaining == nil)
    }

    @Test("estimatedTimeRemaining computes from elapsed and overallProgress")
    func progressETACalculation() throws {
        let progress = RemoteSync.Progress(
            phase: .docs,
            framework: "SwiftUI",
            frameworkIndex: 5,
            frameworksTotal: 20,
            fileIndex: 50,
            filesTotal: 100,
            elapsed: 100,
            overallProgress: 0.25
        )
        let eta = try #require(progress.estimatedTimeRemaining)
        // totalEstimated = 100 / 0.25 = 400, remaining = 400 - 100 = 300
        #expect(eta == 300)
    }
}

// MARK: - IndexState value type

@Suite("RemoteSync.IndexState")
struct RemoteSyncIndexStateTests {
    @Test("Init carries version + defaults the rest")
    func indexStateDefaults() {
        let state = RemoteSync.IndexState(version: "1.2.3")
        #expect(state.version == "1.2.3")
        #expect(state.phase == .docs)
        #expect(state.phasesCompleted.isEmpty)
        #expect(state.currentFramework == nil)
        #expect(state.frameworksCompleted.isEmpty)
        #expect(state.frameworksTotal == 0)
        #expect(state.currentFileIndex == 0)
        #expect(state.filesTotal == 0)
    }

    @Test("startingPhase transitions to the requested phase")
    func indexStateStartingPhase() {
        let state = RemoteSync.IndexState(version: "1.0.0")
            .startingPhase(.evolution, frameworksTotal: 50)
        #expect(state.phase == .evolution)
        #expect(state.frameworksTotal == 50)
        #expect(state.frameworksCompleted.isEmpty)
    }

    @Test("Phase allCases covers docs → evolution → archive → swiftOrg → packages")
    func indexStatePhaseOrder() {
        #expect(RemoteSync.IndexState.Phase.allCases == [.docs, .evolution, .archive, .swiftOrg, .packages])
    }
}

// MARK: - IndexerResult value type

@Suite("RemoteSync.IndexerResult")
struct IndexerResultTests {
    @Test("Success case has no error string")
    func indexerResultSuccess() {
        let result = RemoteSync.IndexerResult(
            uri: "apple-docs://swiftui/View",
            title: "View",
            success: true
        )
        #expect(result.success)
        #expect(result.error == nil)
    }

    @Test("Failure case preserves error string")
    func indexerResultFailure() {
        let result = RemoteSync.IndexerResult(
            uri: "apple-docs://swiftui/View",
            title: "View",
            success: false,
            error: "Network error"
        )
        #expect(!result.success)
        #expect(result.error == "Network error")
    }
}

// MARK: - IndexerError

@Suite("RemoteSync.IndexerError descriptions")
struct IndexerErrorTests {
    @Test("stateVersionMismatch description includes both versions")
    func errorStateVersionMismatch() {
        let err = RemoteSync.IndexerError.stateVersionMismatch(expected: "1.0.0", found: "0.9.0")
        #expect(err.description.contains("1.0.0"))
        #expect(err.description.contains("0.9.0"))
    }

    @Test("phaseNotFound description includes phase string")
    func errorPhaseNotFound() {
        let err = RemoteSync.IndexerError.phaseNotFound("unknown-phase")
        #expect(err.description.contains("unknown-phase"))
    }

    @Test("indexingFailed description includes URI + underlying")
    func errorIndexingFailed() {
        let err = RemoteSync.IndexerError.indexingFailed(uri: "test://uri", underlying: "timeout")
        #expect(err.description.contains("test://uri"))
        #expect(err.description.contains("timeout"))
    }
}

// MARK: - DocumentIndexing protocol witness

@Suite("RemoteSync.DocumentIndexing witness")
struct DocumentIndexingWitnessTests {
    @Test("Concrete conformer satisfies the Strategy contract")
    func conformerCompiles() async throws {
        struct CapturingIndexer: RemoteSync.DocumentIndexing {
            func indexDocument(
                uri _: String,
                source _: String,
                framework _: String?,
                title _: String,
                content _: String,
                jsonData _: String?
            ) async throws {}
        }
        let indexer: any RemoteSync.DocumentIndexing = CapturingIndexer()
        try await indexer.indexDocument(
            uri: "apple-docs://swiftui/View",
            source: "apple-docs",
            framework: "SwiftUI",
            title: "View",
            content: "body",
            jsonData: nil
        )
    }
}

// MARK: - Observer protocol witnesses

@Suite("RemoteSync.IndexerProgressObserving witness")
struct IndexerProgressObservingWitnessTests {
    @Test("Concrete conformer accepts the protocol contract")
    func protocolConformer() {
        struct NoopObserver: RemoteSync.IndexerProgressObserving {
            func observe(progress _: RemoteSync.Progress) {}
        }
        let observer: any RemoteSync.IndexerProgressObserving = NoopObserver()
        observer.observe(progress: RemoteSync.Progress(
            phase: .docs,
            framework: nil,
            frameworkIndex: 0,
            frameworksTotal: 0,
            fileIndex: 0,
            filesTotal: 0,
            elapsed: 0,
            overallProgress: 0
        ))
    }
}

@Suite("RemoteSync.IndexerDocumentObserving witness")
struct IndexerDocumentObservingWitnessTests {
    @Test("Collecting observer captures every observe(result:) call")
    func collectingObserver() {
        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private var uris: [String] = []
            func append(_ uri: String) {
                lock.lock()
                defer { lock.unlock() }
                uris.append(uri)
            }

            var captured: [String] {
                lock.lock()
                defer { lock.unlock() }
                return uris
            }
        }
        let collector = Collector()
        struct CollectingObserver: RemoteSync.IndexerDocumentObserving {
            let collector: Collector
            func observe(result: RemoteSync.IndexerResult) {
                collector.append(result.uri)
            }
        }
        let observer: any RemoteSync.IndexerDocumentObserving = CollectingObserver(collector: collector)
        observer.observe(result: RemoteSync.IndexerResult(uri: "a", title: "A", success: true))
        observer.observe(result: RemoteSync.IndexerResult(uri: "b", title: "B", success: true))
        observer.observe(result: RemoteSync.IndexerResult(uri: "c", title: "C", success: false, error: "boom"))
        #expect(collector.captured == ["a", "b", "c"])
    }
}
