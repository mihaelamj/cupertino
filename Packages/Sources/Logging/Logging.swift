import Foundation

// MARK: - Logging namespace anchor (concrete target)

/// Namespace anchor inside the concrete `Logging` SPM target. Hosts the
/// OSLog + console + file conformer (`Logging.LiveRecording`), plus the
/// legacy static surface (`Logging.Log`, `Logging.ConsoleLogger`,
/// `Logging.Unified`) that's being phased out by the GoF Strategy
/// migration to `Logging.Recording` (defined under the same-named
/// anchor in the sibling `LoggingModels` target).
///
/// Two anchors, one per module, lets either target extend `Logging.*`
/// without dragging the other in: consumers that need only the
/// protocol-typed seam import `LoggingModels` (foundation-only);
/// consumers that own the binary's logger composition root import
/// `Logging` for the production conformer.
public enum Logging {
    // Namespace root - types defined in extensions

    // MARK: - #780 timestamp helper

    /// ISO 8601 timestamp formatter shared by both the actor-side log
    /// path (`Logging.Unified.logToConsole`) and the sync `output(_:)`
    /// passthrough path on `Logging.LiveRecording`.
    ///
    /// Format: `"yyyy-MM-dd'T'HH:mm:ssZZZ"` → `"2026-05-19T02:30:00+0200"`.
    /// Locale-neutral (en_US_POSIX) so the field shape can't change with
    /// the user's regional settings.
    ///
    /// `DateFormatter` is itself thread-safe under iOS 7+/macOS 10.9+
    /// (Apple documentation), so a single shared instance is safe to
    /// call from any concurrent context. Held nonisolated to avoid
    /// dragging actor isolation into every `output(_:)` call site.
    public static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZ"
        return formatter
    }()

    /// Build a "YYYY-MM-DDTHH:MM:SS±HHMM<sep>" prefix for a log line.
    /// Used by `LiveRecording.output(_:)` to keep raw stdout
    /// passthrough lines on the same timestamp cadence as the levelled
    /// `record(...)` lines that go through the actor.
    public static func timestampPrefix(separator: String = "  ") -> String {
        timestampFormatter.string(from: Date()) + separator
    }
}
