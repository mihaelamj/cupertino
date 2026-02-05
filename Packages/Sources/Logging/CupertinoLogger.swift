import Foundation
import OSLog
import Shared

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

// MARK: - Console Output Helpers

/// Helper for outputting to console while also logging
/// Useful for CLI tools that need both user-facing output and logging
extension Logging {
    public enum ConsoleLogger {
        /// Global flag to enable verbose output
        public static var isVerbose: Bool = false

        /// Print to stdout and log as info
        public static func info(_ message: String, logger: os.Logger = Logging.Logger.cli) {
            print(message)
            logger.info(message)
        }

        /// Print to stderr and log as error
        public static func error(_ message: String, logger: os.Logger = Logging.Logger.cli) {
            fputs("\(message)\n", stderr)
            logger.error(message)
        }

        /// Print to stdout only (no logging) - for interactive output
        public static func output(_ message: String) {
            print(message)
        }

        /// Print verbose message to stdout only when verbose mode is enabled
        /// Use for detailed progress information that may clutter normal output
        public static func verbose(_ message: String, logger: os.Logger = Logging.Logger.cli) {
            guard isVerbose else { return }
            print("[verbose] \(message)")
            logger.debug(message)
        }

        /// Print verbose message to stdout only when verbose mode is enabled (no prefix)
        /// Use for detailed progress information that may clutter normal output
        public static func verboseOutput(_ message: String) {
            guard isVerbose else { return }
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
