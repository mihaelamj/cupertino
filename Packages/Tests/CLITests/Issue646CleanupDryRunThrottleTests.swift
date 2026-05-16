@testable import CLI
import Foundation
import SharedConstants
import Testing

// MARK: - #646 — `cleanup --dry-run` no longer floods stdout per file
//
// Pre-fix, `CleanupProgressObserver.observe(progress:)` printed one line
// through `recording.output` per archive across every cleanup run, dry
// or wet. With 619 sample zips and ~80 ms of formatted-print + flush
// per entry, the dry-run command spent ~50 s of its ~60 s elapsed time
// printing — enough to look hung to any caller with a 30-second
// timeout. Real cleanup keeps the per-file output (the work justifies
// it); dry-run now throttles to 20 buckets across the run + the first
// and last entries.
//
// The decision sits in `CLIImpl.Command.Cleanup.shouldEmitProgress(_:dryRun:)`
// (a pure static helper, no observer state, no recorder dependency).
// This suite pins the boundary entries, the stride math, and the
// real-cleanup-stays-verbose contract.

@Suite("#646 cleanup dry-run progress throttle")
struct Issue646CleanupDryRunThrottleTests {
    private func progress(current: Int, total: Int) -> Shared.Models.CleanupProgress {
        Shared.Models.CleanupProgress(
            current: current,
            total: total,
            currentFile: "fixture-\(current).zip",
            originalSize: 0,
            cleanedSize: 0
        )
    }

    // MARK: Real cleanup keeps full verbosity

    @Test("Real cleanup (dryRun = false) emits every entry, even at 619 files")
    func realCleanupKeepsFullVerbosity() {
        for current in 1 ... 619 {
            let prog = progress(current: current, total: 619)
            #expect(CLIImpl.Command.Cleanup.shouldEmitProgress(prog, dryRun: false))
        }
    }

    // MARK: Small batches stay verbose in dry-run

    @Test("Dry-run keeps full verbosity for batches ≤ 50 (per-file output is fast)")
    func dryRunVerboseForSmallBatch() {
        for current in 1 ... 50 {
            let prog = progress(current: current, total: 50)
            #expect(CLIImpl.Command.Cleanup.shouldEmitProgress(prog, dryRun: true))
        }
    }

    @Test("Dry-run starts throttling at the 51-archive boundary")
    func dryRunThrottlesAtFiftyOne() {
        // At total=51 stride = max(1, 51/20) = 2, so odd-indexed entries
        // in the middle of the run drop out.
        let oddMidEntry = progress(current: 3, total: 51)
        let evenMidEntry = progress(current: 4, total: 51)
        #expect(!CLIImpl.Command.Cleanup.shouldEmitProgress(oddMidEntry, dryRun: true))
        #expect(CLIImpl.Command.Cleanup.shouldEmitProgress(evenMidEntry, dryRun: true))
    }

    // MARK: First + last always emit

    @Test("Dry-run always emits the first archive's progress (visible start)")
    func dryRunAlwaysEmitsFirst() {
        let prog = progress(current: 1, total: 619)
        #expect(CLIImpl.Command.Cleanup.shouldEmitProgress(prog, dryRun: true))
    }

    @Test("Dry-run always emits the last archive's progress (visible finish)")
    func dryRunAlwaysEmitsLast() {
        let prog = progress(current: 619, total: 619)
        #expect(CLIImpl.Command.Cleanup.shouldEmitProgress(prog, dryRun: true))
    }

    // MARK: Stride math

    @Test("Dry-run collapses 619 entries to ~22 emissions (first + last + 20 buckets)")
    func dryRunCollapsesLargeBatch() {
        var emissions = 0
        for current in 1 ... 619 {
            let prog = progress(current: current, total: 619)
            if CLIImpl.Command.Cleanup.shouldEmitProgress(prog, dryRun: true) {
                emissions += 1
            }
        }
        // 20 buckets + start + end - any bucket that coincides with the
        // start/end. For 619 files stride = 30 (619/20), so multiples-
        // of-30 from 1...619 = {30, 60, ..., 600} = 20 entries. Plus
        // first (1) + last (619) = 22 distinct emissions.
        #expect(emissions == 22)
    }

    @Test("Dry-run with 1000 archives emits between 18 and 25 lines (4–6% sample density)")
    func dryRunStableRangeFor1000() {
        var emissions = 0
        for current in 1 ... 1000 {
            let prog = progress(current: current, total: 1000)
            if CLIImpl.Command.Cleanup.shouldEmitProgress(prog, dryRun: true) {
                emissions += 1
            }
        }
        #expect(emissions >= 18)
        #expect(emissions <= 25)
    }

    // MARK: Edge cases

    @Test("Dry-run with total = 0 doesn't crash (vacuously emits — never invoked in practice)")
    func dryRunZeroTotal() {
        let prog = progress(current: 0, total: 0)
        // total = 0 → throttleThreshold check fires first (0 <= 50) so
        // the function returns true. The cleaner short-circuits before
        // ever calling observe(progress:) on an empty zipFiles array;
        // pinning the behaviour anyway so future refactors don't
        // accidentally divide by zero in the stride math.
        #expect(CLIImpl.Command.Cleanup.shouldEmitProgress(prog, dryRun: true))
    }

    @Test("Dry-run with total = 1 emits the only entry")
    func dryRunSingleArchive() {
        let prog = progress(current: 1, total: 1)
        #expect(CLIImpl.Command.Cleanup.shouldEmitProgress(prog, dryRun: true))
    }
}
