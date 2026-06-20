import Foundation
import LoggingModels
import OSLog
import SharedConstants

// MARK: - Logger Infrastructure

/// Centralized logging infrastructure for Cupertino using os.log.
/// Provides subsystem-level organization and severity-based filtering.
///
/// 2026-05-26 post-#1056 pluggability follow-up: the previous shape
/// declared 10 hardcoded `public static let <category>` os.Logger
/// instances plus a closed `Logging.Unified.Category` enum + a
/// 10-arm switch + a 10-entry `LiveRecording.categoryMap` dict —
/// 4 edit-points per new source-tier category. Post-fix the source
/// of truth is a single dict keyed by category rawValue; the public
/// API is `Logging.Logger.osLogger(for:)` and consumers reach for
/// it via `LoggingModels.Logging.Category` raw values. Adding a
/// new source's category is one rawValue declaration in
/// `LoggingModels.Logging.Category` (post-#1042 Cluster 10 the
/// struct accepts arbitrary rawValues); unknown categories
/// fall through to `.cli`.
extension Logging {
    public enum Logger {
        /// Main subsystem identifier (`com.cupertino.cli` by default).
        public static let subsystem = Shared.Constants.Logging.subsystem

        /// One os.Logger per shipped category. The composition root
        /// can override entries at construction time via
        /// `Logging.Unified(...,osLoggers:)` for callers that want a
        /// custom subsystem per category (e.g. a test harness that
        /// re-routes to its own subsystem to keep `log show` slices
        /// separable from the production binary's traffic).
        public static let osLoggers: [String: os.Logger] = {
            let categories = [
                "crawler", "mcp", "search", "cli",
                "evolution", "samples", "package-downloader", "archive", "hig",
            ]
            var dict: [String: os.Logger] = [:]
            for category in categories {
                dict[category] = os.Logger(subsystem: subsystem, category: category)
            }
            return dict
        }()

        /// Look up the os.Logger for `category`. Unknown categories
        /// (a future source registering its own rawValue outside the
        /// 9 shipped) fall through to the `.cli` bucket — the safe
        /// default for "general CLI output" instead of crashing.
        ///
        /// Internal categories that don't have a direct
        /// `LoggingModels.Logging.Category.<X>` rawValue alias (e.g.
        /// `.packages` → `"packages"` resolves to the
        /// `package-downloader` subsystem channel) are routed via
        /// the `LiveRecording`-side rawValue map.
        public static func osLogger(for categoryRawValue: String) -> os.Logger {
            osLoggers[categoryRawValue] ?? osLoggers["cli"] ?? os.Logger(subsystem: subsystem, category: "cli")
        }
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log informational message (default level)
    @inlinable
    public func info(_ message: String) {
        info("\(message, privacy: .public)")
    }

    /// Log debug message (for development)
    @inlinable
    public func debug(_ message: String) {
        debug("\(message, privacy: .public)")
    }

    /// Log warning message
    @inlinable
    public func warning(_ message: String) {
        warning("\(message, privacy: .public)")
    }

    /// Log error message
    @inlinable
    public func error(_ message: String) {
        error("\(message, privacy: .public)")
    }

    /// Log critical error message
    @inlinable
    public func critical(_ message: String) {
        critical("\(message, privacy: .public)")
    }

    /// Log fault message (for serious errors)
    @inlinable
    public func fault(_ message: String) {
        fault("\(message, privacy: .public)")
    }
}

// MARK: - Log Viewing Instructions

/*
 View logs using Console.app or command line:

 # View all cupertino logs:
 log show --predicate 'subsystem == "com.cupertino.cli"' --last 1h

 # View specific category:
 log show --predicate 'subsystem == "com.cupertino.cli" AND category == "crawler"' --last 1h

 # Stream live logs:
 log stream --predicate 'subsystem == "com.cupertino.cli"'

 # Filter by severity:
 log show --predicate 'subsystem == "com.cupertino.cli" AND messageType >= "error"' --last 1h
 */
