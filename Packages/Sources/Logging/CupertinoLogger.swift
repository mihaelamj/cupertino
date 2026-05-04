import Foundation
import OSLog
import Shared

// MARK: - Privacy policy
//
// Unified-log entries persist in /var/db/diagnostics. Anything interpolated
// without an explicit privacy level used to default to `.public` here, leaking
// user-supplied paths, URIs, query strings, and third-party error payloads.
//
// Policy now applied across this module:
//   .public    — static identifiers only: log levels, MCP method literals,
//                build constants, fixed enum case descriptions.
//   .private   — DEFAULT for every wrapper. Covers paths, URIs, search
//                queries, tool arguments, error messages, and any value the
//                caller passed in at runtime. Redacted to `<private>` in
//                release; readable on a developer device with the right
//                entitlement.
//   .sensitive — tokens, credentials, env-var values; never readable from
//                the unified log even with debug entitlements.
//
// Callers that genuinely need a literal raised back to `.public` must pass
// `privacy: .public` explicitly.

// MARK: - Logger Infrastructure

/// Centralized logging infrastructure for Cupertino using os.log
/// Provides subsystem-level organization and severity-based filtering
extension Logging {
    public enum Logger {
        // MARK: - Subsystems

        /// Main subsystem identifier
        private static let subsystem = Shared.Constants.Logging.subsystem

        /// Logger for crawler operations
        public static let crawler = os.Logger(subsystem: subsystem, category: "crawler")

        /// Logger for MCP server operations
        public static let mcp = os.Logger(subsystem: subsystem, category: "mcp")

        /// Logger for search index operations
        public static let search = os.Logger(subsystem: subsystem, category: "search")

        /// Logger for CLI operations
        public static let cli = os.Logger(subsystem: subsystem, category: "cli")

        /// Logger for transport layer (stdio, JSON-RPC)
        public static let transport = os.Logger(subsystem: subsystem, category: "transport")

        /// Logger for Swift Evolution operations
        public static let evolution = os.Logger(subsystem: subsystem, category: "evolution")

        /// Logger for sample code downloads
        public static let samples = os.Logger(subsystem: subsystem, category: "samples")

        /// Logger for package documentation downloads
        public static let packageDownloader = os.Logger(subsystem: subsystem, category: "package-downloader")

        /// Logger for Apple archive documentation operations
        public static let archive = os.Logger(subsystem: subsystem, category: "archive")

        /// Logger for Human Interface Guidelines operations
        public static let hig = os.Logger(subsystem: subsystem, category: "hig")
    }
}

// MARK: - Convenience Extensions

/// Discrete privacy levels for the convenience wrappers. We cannot pass an
/// `OSLogPrivacy` value at runtime — the os_log interpolation requires it to
/// be a literal at the call site — so we dispatch to fixed branches.
public enum LogPrivacy: Sendable {
    case `public`
    case `private`
    case sensitive
}

extension Logger {
    /// Log informational message. Defaults to `.private`; pass `.public` only
    /// for static identifiers (see file-level privacy policy).
    @inlinable
    public func info(_ message: String, privacy: LogPrivacy = .private) {
        switch privacy {
        case .public: info("\(message, privacy: .public)")
        case .private: info("\(message, privacy: .private)")
        case .sensitive: info("\(message, privacy: .sensitive)")
        }
    }

    /// Log debug message. Defaults to `.private`.
    @inlinable
    public func debug(_ message: String, privacy: LogPrivacy = .private) {
        switch privacy {
        case .public: debug("\(message, privacy: .public)")
        case .private: debug("\(message, privacy: .private)")
        case .sensitive: debug("\(message, privacy: .sensitive)")
        }
    }

    /// Log warning message. Defaults to `.private`.
    @inlinable
    public func warning(_ message: String, privacy: LogPrivacy = .private) {
        switch privacy {
        case .public: warning("\(message, privacy: .public)")
        case .private: warning("\(message, privacy: .private)")
        case .sensitive: warning("\(message, privacy: .sensitive)")
        }
    }

    /// Log error message. Defaults to `.private`.
    @inlinable
    public func error(_ message: String, privacy: LogPrivacy = .private) {
        switch privacy {
        case .public: error("\(message, privacy: .public)")
        case .private: error("\(message, privacy: .private)")
        case .sensitive: error("\(message, privacy: .sensitive)")
        }
    }

    /// Log critical error message. Defaults to `.private`.
    @inlinable
    public func critical(_ message: String, privacy: LogPrivacy = .private) {
        switch privacy {
        case .public: critical("\(message, privacy: .public)")
        case .private: critical("\(message, privacy: .private)")
        case .sensitive: critical("\(message, privacy: .sensitive)")
        }
    }

    /// Log fault message. Defaults to `.private`.
    @inlinable
    public func fault(_ message: String, privacy: LogPrivacy = .private) {
        switch privacy {
        case .public: fault("\(message, privacy: .public)")
        case .private: fault("\(message, privacy: .private)")
        case .sensitive: fault("\(message, privacy: .sensitive)")
        }
    }
}

// MARK: - Console Output Helpers

/// Helper for outputting to console while also logging
/// Useful for CLI tools that need both user-facing output and logging
extension Logging {
    public enum ConsoleLogger {
        /// Print to stdout and log as info. The unified-log entry defaults
        /// to `.private`; raise to `.public` only for static identifiers.
        public static func info(
            _ message: String,
            logger: os.Logger = Logging.Logger.cli,
            privacy: LogPrivacy = .private
        ) {
            print(message)
            logger.info(message, privacy: privacy)
        }

        /// Print to stderr and log as error. The unified-log entry defaults
        /// to `.private`.
        public static func error(
            _ message: String,
            logger: os.Logger = Logging.Logger.cli,
            privacy: LogPrivacy = .private
        ) {
            fputs("\(message)\n", stderr)
            logger.error(message, privacy: privacy)
        }

        /// Print to stdout only (no logging) - for interactive output
        public static func output(_ message: String) {
            print(message)
        }
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
