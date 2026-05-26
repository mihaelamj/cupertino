import Foundation
@testable import Logging
import LoggingModels
import Testing

// Pins the production conformer that bridges the LoggingModels-side
// `Logging.Recording` Strategy protocol to the actor-backed
// `Logging.Unified` writer. The bridge has two value-type maps (Level
// and Category) — these tests prove both are exhaustive so adding a
// new case to the LoggingModels enum without updating the bridge
// fails loudly in CI.

// MARK: - Conformance witness

@Suite("Logging.LiveRecording conforms to Logging.Recording")
struct LiveRecordingConformanceTests {
    @Test("LiveRecording is constructible and satisfies the protocol")
    func conformsToRecording() {
        let _: any LoggingModels.Logging.Recording = Logging.LiveRecording(
            unified: Logging.Unified(options: .default)
        )
    }
}

// MARK: - record() doesn't crash on any (level × category) combo

@Suite("Logging.LiveRecording.record exhaustive (level × category)")
struct LiveRecordingExhaustiveTests {
    @Test("record() accepts every level × category combo without crashing")
    func recordExhaustive() async {
        // Production routes through a detached task; the assertion is
        // simply "doesn't crash, doesn't throw" across the full matrix.
        // If somebody adds a Level or Category case in LoggingModels
        // without updating the LiveRecording bridge, the switch
        // statements in mapLevel / mapCategory stop being exhaustive
        // and this file fails to compile.
        let recorder = Logging.LiveRecording(unified: Logging.Unified(options: .default))
        for level in [LoggingModels.Logging.Level.debug, .info, .warning, .error] {
            for category in LoggingModels.Logging.Category.allCases {
                recorder.record("test message", level: level, category: category)
            }
        }
        // Let the detached tasks drain so the test runner's pending-task
        // counter is empty before the next case runs.
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test("output() routes to stdout-style passthrough without crashing")
    func outputDoesntCrash() {
        // print() can't be observed inside Swift Testing without
        // reaching into the process's stdout FD; we accept this as a
        // smoke test. Real visibility comes from integration tests that
        // capture the binary's output (Tests/CLITests).
        let recorder = Logging.LiveRecording(unified: Logging.Unified(options: .default))
        recorder.output("user-facing line")
    }
}
