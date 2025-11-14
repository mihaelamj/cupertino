import Foundation
import OSLog

// MARK: - Logger Infrastructure

/// Centralized logging infrastructure for Docsucker using os.log
/// Provides subsystem-level organization and severity-based filtering
public enum DocsuckerLogger {
    // MARK: - Subsystems

    /// Main subsystem identifier
    private static let subsystem = "com.docsucker.appledocsucker"

    /// Logger for crawler operations
    public static let crawler = Logger(subsystem: subsystem, category: "crawler")

    /// Logger for MCP server operations
    public static let mcp = Logger(subsystem: subsystem, category: "mcp")

    /// Logger for search index operations
    public static let search = Logger(subsystem: subsystem, category: "search")

    /// Logger for CLI operations
    public static let cli = Logger(subsystem: subsystem, category: "cli")

    /// Logger for transport layer (stdio, JSON-RPC)
    public static let transport = Logger(subsystem: subsystem, category: "transport")

    /// Logger for PDF export operations
    public static let pdf = Logger(subsystem: subsystem, category: "pdf")

    /// Logger for Swift Evolution operations
    public static let evolution = Logger(subsystem: subsystem, category: "evolution")

    /// Logger for sample code downloads
    public static let samples = Logger(subsystem: subsystem, category: "samples")
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log informational message (default level)
    @inlinable
    public func info(_ message: String) {
        self.info("\(message, privacy: .public)")
    }

    /// Log debug message (for development)
    @inlinable
    public func debug(_ message: String) {
        self.debug("\(message, privacy: .public)")
    }

    /// Log warning message
    @inlinable
    public func warning(_ message: String) {
        self.warning("\(message, privacy: .public)")
    }

    /// Log error message
    @inlinable
    public func error(_ message: String) {
        self.error("\(message, privacy: .public)")
    }

    /// Log critical error message
    @inlinable
    public func critical(_ message: String) {
        self.critical("\(message, privacy: .public)")
    }

    /// Log fault message (for serious errors)
    @inlinable
    public func fault(_ message: String) {
        self.fault("\(message, privacy: .public)")
    }
}

// MARK: - Console Output Helpers

/// Helper for outputting to console while also logging
/// Useful for CLI tools that need both user-facing output and logging
public enum ConsoleLogger {
    /// Print to stdout and log as info
    public static func info(_ message: String, logger: Logger = DocsuckerLogger.cli) {
        print(message)
        logger.info(message)
    }

    /// Print to stderr and log as error
    public static func error(_ message: String, logger: Logger = DocsuckerLogger.cli) {
        fputs("\(message)\n", stderr)
        logger.error(message)
    }

    /// Print to stdout only (no logging) - for interactive output
    public static func output(_ message: String) {
        print(message)
    }
}

// MARK: - Log Viewing Instructions

/*
 View logs using Console.app or command line:

 # View all docsucker logs:
 log show --predicate 'subsystem == "com.docsucker.appledocsucker"' --last 1h

 # View specific category:
 log show --predicate 'subsystem == "com.docsucker.appledocsucker" AND category == "crawler"' --last 1h

 # Stream live logs:
 log stream --predicate 'subsystem == "com.docsucker.appledocsucker"'

 # Filter by severity:
 log show --predicate 'subsystem == "com.docsucker.appledocsucker" AND messageType >= "error"' --last 1h
 */
