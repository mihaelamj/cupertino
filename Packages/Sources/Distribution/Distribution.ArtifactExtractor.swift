import Foundation

// MARK: - Distribution.ArtifactExtractor — concrete extract static func

//
// The `Distribution.ArtifactExtractor` namespace + `TickObserving`
// Observer protocol live in the foundation-only `DistributionModels`
// seam target. This file extends the same enum with the actual
// `extract(...)` static function.

extension Distribution.ArtifactExtractor {
    /// Wraps `/usr/bin/unzip` for cupertino's zip artifacts.
    /// UI-free: callers receive periodic `observeTick()` calls on the
    /// supplied `TickObserving` conformer while the child process is
    /// running so they can render whatever animation they want (CLI
    /// uses a Braille spinner). Returns when the process exits; throws
    /// on non-zero status.
    /// #673 Phase B — default unzip deadline. The v1.2.0 cupertino-databases
    /// zip is ~833 MB; `/usr/bin/unzip` chews through that at 80-150 MB/s
    /// on a typical Mac (~7-12s). Slow-disk worst case (Claw mini external
    /// SSD): ~60s. 600s (10 min) gives ample headroom while still capping
    /// a genuine hang to a finite wait. Caller can override.
    public static let defaultExtractionTimeoutSeconds = 600

    public static func extract(
        zipAt zipURL: URL,
        to destination: URL,
        tickObserver: (any Distribution.ArtifactExtractor.TickObserving)? = nil,
        tickInterval: DispatchTimeInterval = .milliseconds(100),
        timeoutSeconds: Int = Distribution.ArtifactExtractor.defaultExtractionTimeoutSeconds
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Optional ticker for spinners / heartbeats. Stops automatically
        // when the process terminates.
        var timer: DispatchSourceTimer?
        if let tickObserver {
            let ticker = DispatchSource.makeTimerSource(queue: .global())
            ticker.schedule(deadline: .now(), repeating: tickInterval)
            ticker.setEventHandler {
                tickObserver.observeTick()
            }
            timer = ticker
            ticker.resume()
        }
        defer { timer?.cancel() }

        // #673 Phase B — per-extraction deadline. If `unzip` runs past
        // `timeoutSeconds`, force-terminate it and surface a typed
        // `.extractionTimeout` rather than letting the continuation hang
        // forever. SIGTERM gives the child a chance to clean up; the
        // terminationHandler then resumes with a non-zero status, which
        // we convert below into the timeout error.
        let timedOutBox = TimedOutBox()
        let timeoutTask = Task { [weak process] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            await timedOutBox.markTimedOut()
            if process?.isRunning == true {
                process?.terminate()
            }
        }
        defer { timeoutTask.cancel() }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        if await timedOutBox.didTimeOut {
            throw Distribution.SetupError.extractionTimeout(seconds: timeoutSeconds)
        }
        guard status == 0 else {
            throw Distribution.SetupError.extractionFailed
        }
    }

    /// #673 Phase B — actor-isolated flag for the deadline-fired path so the
    /// post-await branch knows whether the non-zero status came from a
    /// natural error or from our SIGTERM.
    private actor TimedOutBox {
        private(set) var didTimeOut = false
        func markTimedOut() {
            didTimeOut = true
        }
    }
}
