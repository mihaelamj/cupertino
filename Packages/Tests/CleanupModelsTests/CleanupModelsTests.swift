import CleanupModels
import Foundation
import SharedConstants
import Testing

// MARK: - CleanupModels public surface smoke tests
//
// CleanupModels is the foundation-only seam target for the
// `Sample.Cleanup.Cleaner` actor (extracted in the closures-to-Observer
// epic). It owns one GoF Observer protocol:
// `Sample.Cleanup.CleanerProgressObserving`. The payload type is
// `Shared.Models.CleanupProgress`, which already lives in foundation-
// tier `SharedConstants`.
//
// These tests pin the public surface so a rename or accidental
// deletion fails CI before downstream consumers (Cleanup producer,
// CLI) discover it. Also satisfies the "every test target must have
// at least one .swift file" rule that PRs #558 + #563 violated.

// MARK: - Namespace anchor

@Suite("Sample.Cleanup namespace anchor")
struct SampleCleanupNamespaceTests {
    @Test("Sample.Cleanup namespace is reachable")
    func sampleCleanupNamespaceExists() {
        // The Sample.Cleanup enum is owned by SharedConstants (see
        // Packages/Sources/Shared/Sample.swift). CleanupModels extends
        // it to add the CleanerProgressObserving protocol. Reaching
        // it through CleanupModels proves the extension wiring works.
        let _: Sample.Cleanup.Type = Sample.Cleanup.self
    }
}

// MARK: - CleanerProgressObserving protocol witness

@Suite("Sample.Cleanup.CleanerProgressObserving witness")
struct CleanerProgressObservingWitnessTests {
    @Test("Concrete conformer accepts the protocol contract")
    func protocolConformer() {
        struct NoopObserver: Sample.Cleanup.CleanerProgressObserving {
            func observe(progress: Shared.Models.CleanupProgress) {}
        }
        let observer: any Sample.Cleanup.CleanerProgressObserving = NoopObserver()
        observer.observe(progress: Shared.Models.CleanupProgress(
            current: 1,
            total: 10,
            currentFile: "test.zip",
            originalSize: 1000,
            cleanedSize: 800
        ))
    }

    @Test("Counting observer increments per observe(progress:) call")
    func countingObserverIntegration() {
        // Sendable counter so the observer can hold a reference.
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func increment() {
                lock.lock()
                defer { lock.unlock() }
                count += 1
            }
            var value: Int {
                lock.lock()
                defer { lock.unlock() }
                return count
            }
        }
        let counter = Counter()
        struct CountingObserver: Sample.Cleanup.CleanerProgressObserving {
            let counter: Counter
            func observe(progress: Shared.Models.CleanupProgress) {
                counter.increment()
            }
        }
        let observer: any Sample.Cleanup.CleanerProgressObserving = CountingObserver(counter: counter)
        observer.observe(progress: Shared.Models.CleanupProgress(
            current: 1, total: 3, currentFile: "a.zip",
            originalSize: 100, cleanedSize: 50
        ))
        observer.observe(progress: Shared.Models.CleanupProgress(
            current: 2, total: 3, currentFile: "b.zip",
            originalSize: 200, cleanedSize: 150
        ))
        observer.observe(progress: Shared.Models.CleanupProgress(
            current: 3, total: 3, currentFile: "c.zip",
            originalSize: 300, cleanedSize: 250
        ))
        #expect(counter.value == 3)
    }
}
