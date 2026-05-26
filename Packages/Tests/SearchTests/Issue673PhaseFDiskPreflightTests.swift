import Diagnostics
import Foundation
import SharedConstants
import Testing

// MARK: - #673 Phase F — disk-space preflight

//
// `Diagnostics.DiskPreflight.check(...)` refuses to start a write
// operation when free disk wouldn't cover the operation's peak
// transient size + safety margin. Carmack class-of-bug from the
// 2026-05-16 corruption: `cupertino save` started on a 95%-full disk,
// partial-wrote 2.48 GB → 429 MB search.db, crashed mid-FTS insert.
// This suite pins that refusing-up-front is mandatory.
//
// Tests use the `diskUsageProvider:` test seam to inject synthetic
// `DiskUsage` values — no actual statfs calls, no tmpfs setup, no
// machine-specific assumptions.

@Suite("#673 Phase F — disk-space preflight", .serialized)
struct Issue673PhaseFDiskPreflightTests {
    // MARK: - Helpers

    private func usage(free: Int64, total: Int64) -> Diagnostics.Probes.DiskUsage {
        Diagnostics.Probes.DiskUsage(totalBytes: total, freeBytes: free)
    }

    private func provider(returning usage: Diagnostics.Probes.DiskUsage?) -> (URL) -> Diagnostics.Probes.DiskUsage? {
        { _ in usage }
    }

    // MARK: - `.ok` cases

    @Test("Free disk well above estimate + margin → .ok")
    func plentyOfRoomReturnsOk() {
        // 250 GB free / 500 GB total = 50% free fraction (above the
        // 20% warningFraction default), 1 GB estimate × 1.10 = 1.1 GB
        // needed — comfortable .ok on both axes.
        let result = Diagnostics.DiskPreflight.check(
            targetDirectory: URL(fileURLWithPath: "/tmp"),
            estimatedBytes: 1000000000, // 1 GB
            diskUsageProvider: provider(returning: usage(free: 250000000000, total: 500000000000))
        )
        guard case .ok = result else {
            Issue.record("expected .ok with plenty of room; got \(result)")
            return
        }
    }

    @Test("Probe returning nil falls through to .ok (can't refuse what we can't measure)")
    func unreadableVolumeFallsThroughToOk() {
        let result = Diagnostics.DiskPreflight.check(
            targetDirectory: URL(fileURLWithPath: "/some/bogus/path"),
            estimatedBytes: 1000000000,
            diskUsageProvider: provider(returning: nil)
        )
        guard case .ok = result else {
            Issue.record("expected .ok when probe returns nil; got \(result)")
            return
        }
    }

    // MARK: - `.warningLow` cases

    @Test("Estimate fits but free fraction < warningFraction → .warningLow")
    func tightButFitsReturnsWarning() {
        // 16 GB free out of 100 GB total = 16% free (below default 20% warning).
        // Estimate 1 GB + 10% margin = 1.1 GB needed; 16 GB > 1.1 GB so it fits.
        let result = Diagnostics.DiskPreflight.check(
            targetDirectory: URL(fileURLWithPath: "/tmp"),
            estimatedBytes: 1000000000,
            diskUsageProvider: provider(returning: usage(free: 16000000000, total: 100000000000))
        )
        guard case .warningLow(_, _, let fraction) = result else {
            Issue.record("expected .warningLow on 16% free; got \(result)")
            return
        }
        #expect(fraction < 0.20, "warning fraction should be below threshold; got \(fraction)")
    }

    // MARK: - `.refuseInsufficient` cases (the headline behaviour)

    @Test("Free disk < estimate × 1.10 → .refuseInsufficient (the headline case)")
    func tooLowRefusesWithRawNumbers() {
        // 2 GB estimate, 1.5 GB free → needed = 2.2 GB, short by 0.7 GB → refuse.
        let result = Diagnostics.DiskPreflight.check(
            targetDirectory: URL(fileURLWithPath: "/tmp"),
            estimatedBytes: 2000000000,
            diskUsageProvider: provider(returning: usage(free: 1500000000, total: 500000000000))
        )
        guard case .refuseInsufficient(let needed, let free, let path) = result else {
            Issue.record("expected .refuseInsufficient on low free; got \(result)")
            return
        }
        #expect(needed == 2200000000, "needed should be estimate × 1.10 = 2.2 GB; got \(needed)")
        #expect(free == 1500000000)
        #expect(path == "/tmp")
    }

    @Test("Free disk exactly at estimate + margin → .ok (not refused)")
    func exactlyAtThresholdIsOk() {
        // 1 GB estimate, free exactly at 1.1 GB (= estimate × 1.10).
        // Should be .ok (not .refuseInsufficient) — the threshold is
        // "less than", not "less than or equal".
        let result = Diagnostics.DiskPreflight.check(
            targetDirectory: URL(fileURLWithPath: "/tmp"),
            estimatedBytes: 1000000000,
            // Free fraction 50% so we don't trip warningLow.
            diskUsageProvider: provider(returning: usage(free: 1100000000, total: 2200000000))
        )
        guard case .ok = result else {
            Issue.record("expected .ok at exact threshold; got \(result)")
            return
        }
    }

    @Test("Custom marginFraction = 0.5 raises the bar")
    func customMarginRaisesThreshold() {
        // 1 GB estimate + 50% margin = 1.5 GB needed. 1.3 GB free → refuse.
        let result = Diagnostics.DiskPreflight.check(
            targetDirectory: URL(fileURLWithPath: "/tmp"),
            estimatedBytes: 1000000000,
            marginFraction: 0.5,
            diskUsageProvider: provider(returning: usage(free: 1300000000, total: 500000000000))
        )
        guard case .refuseInsufficient(let needed, _, _) = result else {
            Issue.record("expected .refuseInsufficient with 50% margin; got \(result)")
            return
        }
        #expect(needed == 1500000000)
    }

    // MARK: - `InsufficientDiskSpaceError` shape

    @Test("InsufficientDiskSpaceError.errorDescription names path / needed / free / short")
    func errorDescriptionIsUserFriendly() {
        let error = Diagnostics.InsufficientDiskSpaceError(
            neededBytes: 4400000000, // 4.4 GB
            freeBytes: 1500000000, // 1.5 GB
            path: "/Users/x/.cupertino"
        )
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("/Users/x/.cupertino"), "path should appear; got: \(desc)")
        // ByteCountFormatter respects the locale's decimal separator,
        // so we can't assert "4.4 GB" verbatim (a comma-locale machine
        // renders "4,4 GB"). Assert on the unit + magnitude digit only.
        #expect(
            desc.range(of: #"4[.,]4 GB"#, options: .regularExpression) != nil
                || desc.range(of: #"\b4 GB"#, options: .regularExpression) != nil,
            "needed (~4.4 GB) should appear; got: \(desc)"
        )
        #expect(
            desc.range(of: #"1[.,]5 GB"#, options: .regularExpression) != nil
                || desc.range(of: #"\b1 GB"#, options: .regularExpression) != nil,
            "free (~1.5 GB) should appear; got: \(desc)"
        )
        // Must not leak Swift stack trace shapes.
        #expect(desc.contains("InsufficientDiskSpaceError") == false, "errorDescription leaked the type name")
        #expect(desc.contains(".swift") == false, "errorDescription leaked a Swift source file path")
        #expect(desc.contains("Insufficient disk space"), "should name the class of problem; got: \(desc)")
    }

    // MARK: - Per-command estimate constants

    @Test("Shared.Constants.DiskBudget values are sane (positive + match commented rationale)")
    func diskBudgetConstantsArePositive() {
        // Pin per-command estimates so a future "let me bump the FTS size"
        // bundle-growth doesn't silently slip past the preflight. Values
        // here mirror the rationale comments in Shared.Constants.DiskBudget.
        #expect(Shared.Constants.DiskBudget.docsSaveBytes == 4 * 1024 * 1024 * 1024, "docs save = 4 GB")
        #expect(Shared.Constants.DiskBudget.samplesSaveBytes == 500 * 1024 * 1024, "samples save = 500 MB")
        #expect(Shared.Constants.DiskBudget.packagesSaveBytes == 200 * 1024 * 1024, "packages save = 200 MB")
        #expect(Shared.Constants.DiskBudget.setupBytes == 4 * 1024 * 1024 * 1024, "setup = 4 GB")
        #expect(Shared.Constants.DiskBudget.fetchBytes == 5 * 1024 * 1024 * 1024, "fetch = 5 GB")
        // All values positive.
        #expect(Shared.Constants.DiskBudget.docsSaveBytes > 0)
        #expect(Shared.Constants.DiskBudget.samplesSaveBytes > 0)
        #expect(Shared.Constants.DiskBudget.packagesSaveBytes > 0)
        #expect(Shared.Constants.DiskBudget.setupBytes > 0)
        #expect(Shared.Constants.DiskBudget.fetchBytes > 0)
    }
}
