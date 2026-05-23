import Foundation
import LoggingModels

// MARK: - User-facing diagnostic helper

extension CLIImpl {
    /// Print a user-facing diagnostic to stderr AND attempt to log
    /// it at `.error` level. The synchronous `FileHandle.standardError
    /// .write(...)` is the load-bearing call: bytes land in the
    /// kernel pipe before the caller's subsequent `throw ExitCode
    /// .failure` tears down the process, so terminal users +
    /// subprocess-stderr-capturing harnesses reliably see the
    /// message. The follow-on `recording.error(...)` log call is
    /// best-effort: `Logging.LiveRecording.record` typically
    /// dispatches into a detached actor task that may not drain
    /// before process exit, so OSLog may miss the record on negative
    /// paths. For audit / observability purposes, prefer the stderr
    /// capture; OSLog should only be relied on for non-fatal
    /// recordings.
    ///
    /// Required for negative-path messages on `cupertino inheritance`
    /// (disambiguation, framework-filter miss) and `cupertino read`
    /// (URI not found, source mismatch) per #953. Pre-#953 these
    /// paths went through `recording.error(...)` only, which made the
    /// terminal user see exit-1 with no output at all, and MCP-style
    /// agent clients could not distinguish "tool failed" from
    /// "tool succeeded with empty result."
    ///
    /// Unix convention: stdout is for command output, stderr is for
    /// diagnostics. Helper writes to stderr so successful command
    /// stdout (e.g. an inheritance chain) is not polluted.
    static func printUserFacingDiagnostic(
        _ message: String,
        recording: any LoggingModels.Logging.Recording
    ) {
        let trimmed = message.hasSuffix("\n") ? message : message + "\n"
        FileHandle.standardError.write(Data(trimmed.utf8))
        recording.error(message)
    }
}
