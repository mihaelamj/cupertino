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
    public static func extract(
        zipAt zipURL: URL,
        to destination: URL,
        tickObserver: (any Distribution.ArtifactExtractor.TickObserving)? = nil,
        tickInterval: DispatchTimeInterval = .milliseconds(100)
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

        guard status == 0 else {
            throw Distribution.SetupError.extractionFailed
        }
    }
}
