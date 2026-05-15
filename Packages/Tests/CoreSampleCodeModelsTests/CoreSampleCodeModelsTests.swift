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

// MARK: - Sample.Core.Progress + Statistics + DownloaderProgressObserving

@Suite("Sample.Core.Progress + Statistics value types")
struct SampleCoreProgressValueTypeTests {
    @Test("Statistics defaults to zero counters and nil time bounds")
    func statisticsDefaults() {
        let stats = Sample.Core.Statistics()
        #expect(stats.totalSamples == 0)
        #expect(stats.downloadedSamples == 0)
        #expect(stats.skippedSamples == 0)
        #expect(stats.errors == 0)
        #expect(stats.startTime == nil)
        #expect(stats.endTime == nil)
        #expect(stats.duration == nil)
    }

    @Test("Statistics duration = end - start when both set")
    func statisticsDurationComputed() throws {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 42)
        let stats = Sample.Core.Statistics(startTime: start, endTime: end)
        let duration = try #require(stats.duration)
        #expect(duration == 42)
    }

    @Test("Progress carries all fields verbatim and computes percentage")
    func progressMemberwiseAndPercentage() {
        let stats = Sample.Core.Statistics(totalSamples: 100)
        let progress = Sample.Core.Progress(
            current: 25,
            total: 100,
            sampleName: "Fruta",
            stats: stats
        )
        #expect(progress.current == 25)
        #expect(progress.total == 100)
        #expect(progress.sampleName == "Fruta")
        #expect(progress.stats.totalSamples == 100)
        #expect(progress.percentage == 25)
    }
}

@Suite("Sample.Core.DownloaderProgressObserving witness")
struct DownloaderProgressObservingWitnessTests {
    @Test("Concrete conformer accepts the protocol contract")
    func protocolConformer() {
        struct NoopObserver: Sample.Core.DownloaderProgressObserving {
            func observe(progress _: Sample.Core.Progress) {}
        }
        let observer: any Sample.Core.DownloaderProgressObserving = NoopObserver()
        observer.observe(progress: Sample.Core.Progress(
            current: 1,
            total: 10,
            sampleName: "x",
            stats: Sample.Core.Statistics()
        ))
    }

    @Test("Collecting observer captures every observe(progress:) call")
    func collectingObserverIntegration() {
        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private var captured: [String] = []
            func append(_ name: String) {
                lock.lock()
                defer { lock.unlock() }
                captured.append(name)
            }

            var snapshot: [String] {
                lock.lock()
                defer { lock.unlock() }
                return captured
            }
        }
        let collector = Collector()
        struct CollectingObserver: Sample.Core.DownloaderProgressObserving {
            let collector: Collector
            func observe(progress: Sample.Core.Progress) {
                collector.append(progress.sampleName)
            }
        }
        let observer: any Sample.Core.DownloaderProgressObserving = CollectingObserver(collector: collector)
        for (i, name) in ["a", "b", "c"].enumerated() {
            observer.observe(progress: Sample.Core.Progress(
                current: i + 1,
                total: 3,
                sampleName: name,
                stats: Sample.Core.Statistics()
            ))
        }
        #expect(collector.snapshot == ["a", "b", "c"])
    }
}
