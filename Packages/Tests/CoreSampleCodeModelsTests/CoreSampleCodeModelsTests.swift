import CoreSampleCodeModels
import Foundation
import SharedConstants
import Testing

// MARK: - CoreSampleCodeModels public surface smoke tests

//
// CoreSampleCodeModels is the foundation-only seam target for the
// `CoreSampleCode` producer (extracted in the closures-to-Observer
// epic). It owns:
// - `Sample.Core.GitHubFetcherProgress` Sendable value type
// - `Sample.Core.GitHubFetcherProgressObserving` GoF Observer protocol
//
// These tests pin the public surface so a rename or accidental
// deletion fails CI before downstream consumers discover it.

// MARK: - Namespace anchor

@Suite("Sample.Core namespace anchor (via seam)")
struct SampleCoreNamespaceTests {
    @Test("Sample.Core namespace is reachable through CoreSampleCodeModels")
    func sampleCoreNamespaceExists() {
        // The Sample.Core enum is owned by SharedConstants (see
        // Packages/Sources/Shared/Sample.swift). CoreSampleCodeModels
        // extends it to add the GitHubFetcher types. Reaching it
        // through CoreSampleCodeModels proves the extension wiring
        // works.
        let _: Sample.Core.Type = Sample.Core.self
    }
}

// MARK: - GitHubFetcherProgress value type

@Suite("Sample.Core.GitHubFetcherProgress")
struct GitHubFetcherProgressTests {
    @Test("Stores both fields via init")
    func progressRoundTrip() {
        let progress = Sample.Core.GitHubFetcherProgress(
            message: "Cloning…",
            percentage: 42.5
        )
        #expect(progress.message == "Cloning…")
        #expect(progress.percentage == 42.5)
    }

    @Test("percentage nil when caller doesn't have one (e.g. opaque clone progress)")
    func progressNilPercentage() {
        let progress = Sample.Core.GitHubFetcherProgress(message: "Resolving deltas")
        #expect(progress.message == "Resolving deltas")
        #expect(progress.percentage == nil)
    }
}

// MARK: - GitHubFetcherProgressObserving protocol witness

@Suite("Sample.Core.GitHubFetcherProgressObserving witness")
struct GitHubFetcherProgressObservingWitnessTests {
    @Test("Concrete conformer accepts the protocol contract")
    func protocolConformer() {
        struct NoopObserver: Sample.Core.GitHubFetcherProgressObserving {
            func observe(progress: Sample.Core.GitHubFetcherProgress) {}
        }
        let observer: any Sample.Core.GitHubFetcherProgressObserving = NoopObserver()
        observer.observe(progress: Sample.Core.GitHubFetcherProgress(
            message: "test",
            percentage: 50
        ))
    }

    @Test("Collecting observer captures every observe(progress:) call")
    func collectingObserverIntegration() {
        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private var messages: [String] = []
            func append(_ message: String) {
                lock.lock()
                defer { lock.unlock() }
                messages.append(message)
            }

            var captured: [String] {
                lock.lock()
                defer { lock.unlock() }
                return messages
            }
        }
        let collector = Collector()
        struct CollectingObserver: Sample.Core.GitHubFetcherProgressObserving {
            let collector: Collector
            func observe(progress: Sample.Core.GitHubFetcherProgress) {
                collector.append(progress.message)
            }
        }
        let observer: any Sample.Core.GitHubFetcherProgressObserving = CollectingObserver(collector: collector)
        observer.observe(progress: Sample.Core.GitHubFetcherProgress(message: "a"))
        observer.observe(progress: Sample.Core.GitHubFetcherProgress(message: "b"))
        observer.observe(progress: Sample.Core.GitHubFetcherProgress(message: "c"))
        #expect(collector.captured == ["a", "b", "c"])
    }
}
