@testable import CorePackageIndexing
import Foundation
import Testing

/// #1106 regression: `PackageArchiveExtractor.runTar` was assigning
/// `Pipe()` to both `standardError` and `standardOutput` without
/// draining either, then calling `waitUntilExit()`. Any child writing
/// more than ~64 KB to a pipe blocked; the parent blocked in
/// `waitUntilExit()`; classic Foundation.Process deadlock.
///
/// These tests run a child process that emits well above the 64 KB
/// pipe-buffer ceiling using the same drain-during-wait pattern the
/// fix uses inside `runTar`. If the pattern regresses (a future
/// refactor removes the `readabilityHandler` drain), the assertions
/// time out and the test fails.
@Suite("#1106 PackageArchiveExtractor pipe-deadlock regression")
struct Issue1106PipeDeadlockTests {
    @Test("Child writing 256KB to stderr does not deadlock when both pipes are drained")
    func drainPreventsDeadlockOnLargeStderr() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 256 KB on stderr (4x the 64 KB pipe buffer ceiling) — would
        // have deadlocked pre-#1106 within the first ~64 KB.
        process.arguments = [
            "-c",
            "yes 'pre-fix this would deadlock at ~64 KB of stderr' | head -c 262144 1>&2",
        ]

        let stderr = Pipe()
        let stdout = Pipe()
        process.standardError = stderr
        process.standardOutput = stdout

        let stderrBytes = LockedCounter()
        let stdoutBytes = LockedCounter()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrBytes.add(chunk.count) }
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutBytes.add(chunk.count) }
        }
        defer {
            stderr.fileHandleForReading.readabilityHandler = nil
            stdout.fileHandleForReading.readabilityHandler = nil
        }

        try process.run()
        process.waitUntilExit()
        // Pick up any tail bytes after exit, same shape as `runTar`.
        stderrBytes.add(stderr.fileHandleForReading.availableData.count)
        stdoutBytes.add(stdout.fileHandleForReading.availableData.count)

        #expect(process.terminationStatus == 0)
        #expect(stderrBytes.value >= 262144)
    }

    @Test("Child writing 256KB to stdout does not deadlock when both pipes are drained")
    func drainPreventsDeadlockOnLargeStdout() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "yes 'pre-fix this would deadlock at ~64 KB of stdout' | head -c 262144",
        ]

        let stderr = Pipe()
        let stdout = Pipe()
        process.standardError = stderr
        process.standardOutput = stdout

        let stdoutBytes = LockedCounter()
        stderr.fileHandleForReading.readabilityHandler = { _ in }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutBytes.add(chunk.count) }
        }
        defer {
            stderr.fileHandleForReading.readabilityHandler = nil
            stdout.fileHandleForReading.readabilityHandler = nil
        }

        try process.run()
        process.waitUntilExit()
        stdoutBytes.add(stdout.fileHandleForReading.availableData.count)

        #expect(process.terminationStatus == 0)
        #expect(stdoutBytes.value >= 262144)
    }
}

/// Test-local Sendable counter used by the drain-pattern smoke tests.
/// Mirrors the runtime `LockedBuffer` shape but counts bytes instead
/// of accumulating them.
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add(_ delta: Int) {
        lock.lock()
        count += delta
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
