import Foundation

extension Distribution {
    /// Wraps `/usr/bin/unzip` for cupertino's zip artifacts.
    /// UI-free: callers receive a single `tickHandler` callback while the
    /// child process is running so they can render whatever animation they
    /// want (CLI uses a Braille spinner). Returns when the process exits;
    /// throws on non-zero status.
    public enum ArtifactExtractor {
        public static func extract(
            zipAt zipURL: URL,
            to destination: URL,
            tickHandler: (@Sendable () -> Void)? = nil,
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
            if let tickHandler {
                let ticker = DispatchSource.makeTimerSource(queue: .global())
                ticker.schedule(deadline: .now(), repeating: tickInterval)
                ticker.setEventHandler {
                    tickHandler()
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
}
