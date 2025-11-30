import Foundation
import OSLog
import Shared

// MARK: - Unified Logger

/// Unified logging system with three configurable outputs:
/// 1. os.log (always on) - system log for debugging via `log show`
/// 2. Console (configurable) - stdout/stderr for user feedback
/// 3. File (optional) - for crash debugging and long-running operations
///
/// Usage:
/// ```swift
/// let log = UnifiedLogger.shared
/// log.info("Starting crawl...")
/// log.error("Failed to fetch page")
/// log.debug("Detailed state: \(state)")
/// ```
public actor UnifiedLogger {
    // MARK: - Singleton

    /// Shared logger instance
    public static let shared = UnifiedLogger()

    // MARK: - Log Level

    /// Log severity levels
    public enum Level: Int, Sendable, Comparable, CustomStringConvertible {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        public static func <(lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var description: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERROR"
            }
        }

        /// Emoji prefix for console output
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }

    // MARK: - Category

    /// Log categories for filtering
    public enum Category: String, Sendable {
        case crawler
        case mcp
        case search
        case cli
        case transport
        case evolution
        case samples
        case packages

        /// Get the os.Logger for this category
        var osLogger: os.Logger {
            switch self {
            case .crawler: return Logging.Logger.crawler
            case .mcp: return Logging.Logger.mcp
            case .search: return Logging.Logger.search
            case .cli: return Logging.Logger.cli
            case .transport: return Logging.Logger.transport
            case .evolution: return Logging.Logger.evolution
            case .samples: return Logging.Logger.samples
            case .packages: return Logging.Logger.packageDownloader
            }
        }
    }

    // MARK: - Configuration

    /// Logger configuration options
    public struct Options: Sendable {
        /// Enable console output (stdout/stderr)
        public var consoleEnabled: Bool

        /// Enable file logging
        public var fileEnabled: Bool

        /// File URL for logging (defaults to ~/.cupertino/cupertino.log)
        public var fileURL: URL?

        /// Minimum log level to output
        public var minLevel: Level

        /// Include timestamps in console output
        public var showTimestamps: Bool

        /// Include category in console output
        public var showCategory: Bool

        /// Default options based on build configuration
        public static var `default`: Options {
            #if DEBUG
            return Options(
                consoleEnabled: true,
                fileEnabled: true,
                fileURL: nil,
                minLevel: .debug,
                showTimestamps: true,
                showCategory: true
            )
            #else
            return Options(
                consoleEnabled: true,
                fileEnabled: false,
                fileURL: nil,
                minLevel: .info,
                showTimestamps: false,
                showCategory: false
            )
            #endif
        }

        public init(
            consoleEnabled: Bool = true,
            fileEnabled: Bool = false,
            fileURL: URL? = nil,
            minLevel: Level = .info,
            showTimestamps: Bool = false,
            showCategory: Bool = false
        ) {
            self.consoleEnabled = consoleEnabled
            self.fileEnabled = fileEnabled
            self.fileURL = fileURL
            self.minLevel = minLevel
            self.showTimestamps = showTimestamps
            self.showCategory = showCategory
        }
    }

    // MARK: - Properties

    private var options: Options
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private var isInitialized: Bool = false

    // MARK: - Initialization

    private init(options: Options = .default) {
        self.options = options
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        // File logging setup is deferred to first log call
    }

    /// Ensure file logging is set up (called lazily)
    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true

        if options.fileEnabled {
            setupFileLogging()
        }
    }

    // MARK: - Configuration

    /// Configure the logger with new options
    public func configure(_ newOptions: Options) {
        // Close existing file handle if any
        if let handle = fileHandle {
            try? handle.close()
            fileHandle = nil
        }

        options = newOptions

        if options.fileEnabled {
            setupFileLogging()
        }
    }

    /// Enable file logging to the specified path
    public func enableFileLogging(at url: URL? = nil) {
        options.fileEnabled = true
        options.fileURL = url
        setupFileLogging()
    }

    /// Disable file logging
    public func disableFileLogging() {
        options.fileEnabled = false
        if let handle = fileHandle {
            try? handle.close()
            fileHandle = nil
        }
    }

    /// Disable console output (useful for MCP server mode)
    public func disableConsole() {
        options.consoleEnabled = false
    }

    /// Enable console output
    public func enableConsole() {
        options.consoleEnabled = true
    }

    /// Set minimum log level
    public func setMinLevel(_ level: Level) {
        options.minLevel = level
    }

    // MARK: - File Setup

    private func setupFileLogging() {
        let fileURL = options.fileURL ?? defaultLogFileURL()

        // Create directory if needed
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Create or open file
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            fileHandle = try FileHandle(forWritingTo: fileURL)
            try fileHandle?.seekToEnd()

            // Write session start marker
            let marker = "\n--- Log session started at \(dateFormatter.string(from: Date())) ---\n"
            let data = Data(marker.utf8)
            try fileHandle?.write(contentsOf: data)
        } catch {
            // Silently fail - don't crash if logging fails
            fileHandle = nil
        }
    }

    private func defaultLogFileURL() -> URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir
            .appendingPathComponent(".cupertino")
            .appendingPathComponent("cupertino.log")
    }

    // MARK: - Logging Methods

    /// Log a debug message
    public func debug(
        _ message: String,
        category: Category = .cli,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    /// Log an info message
    public func info(
        _ message: String,
        category: Category = .cli,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    /// Log a warning message
    public func warning(
        _ message: String,
        category: Category = .cli,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    /// Log an error message
    public func error(
        _ message: String,
        category: Category = .cli,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    // MARK: - Core Logging

    private func log(
        _ message: String,
        level: Level,
        category: Category,
        file: String,
        function: String,
        line: Int
    ) {
        // Lazy initialization
        ensureInitialized()

        // Check minimum level
        guard level >= options.minLevel else { return }

        // 1. Always log to os.log
        logToOSLog(message, level: level, category: category)

        // 2. Log to console if enabled
        if options.consoleEnabled {
            logToConsole(message, level: level, category: category)
        }

        // 3. Log to file if enabled
        if options.fileEnabled, fileHandle != nil {
            logToFile(message, level: level, category: category, file: file, function: function, line: line)
        }
    }

    private func logToOSLog(_ message: String, level: Level, category: Category) {
        let logger = category.osLogger
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
    }

    private func logToConsole(_ message: String, level: Level, category: Category) {
        var output = ""

        if options.showTimestamps {
            output += "[\(dateFormatter.string(from: Date()))] "
        }

        if options.showCategory {
            output += "[\(category.rawValue)] "
        }

        output += message

        switch level {
        case .debug, .info:
            print(output)
        case .warning, .error:
            fputs("\(output)\n", stderr)
        }
    }

    private func logToFile(
        _ message: String,
        level: Level,
        category: Category,
        file: String,
        function: String,
        line: Int
    ) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logLine = "[\(timestamp)] [\(level)] [\(category.rawValue)] \(fileName):\(line) \(function) - \(message)\n"

        let data = Data(logLine.utf8)
        try? fileHandle?.write(contentsOf: data)
    }

    // MARK: - Cleanup

    deinit {
        // Note: This won't be called for actors, but keeping for documentation
    }

    /// Flush and close the log file
    public func close() {
        if let handle = fileHandle {
            try? handle.synchronize()
            try? handle.close()
            fileHandle = nil
        }
    }
}

// MARK: - Synchronous Logging (for non-async contexts)

/// Synchronous logger for use in non-async contexts
/// Uses nonisolated(unsafe) to allow synchronous access - logging is fire-and-forget
public enum Log {
    /// Shared options for synchronous logging
    private nonisolated(unsafe) static var options = UnifiedLogger.Options.default
    private nonisolated(unsafe) static var fileHandle: FileHandle?
    private nonisolated(unsafe) static var isInitialized = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Configure synchronous logger options
    public static func configure(_ newOptions: UnifiedLogger.Options) {
        options = newOptions
        isInitialized = false
        ensureInitialized()
    }

    /// Disable console output (for MCP server mode)
    public static func disableConsole() {
        options.consoleEnabled = false
    }

    /// Enable console output
    public static func enableConsole() {
        options.consoleEnabled = true
    }

    private static func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true

        if options.fileEnabled {
            setupFileLogging()
        }
    }

    private static func setupFileLogging() {
        let fileURL = options.fileURL ?? defaultLogFileURL()
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            fileHandle = try FileHandle(forWritingTo: fileURL)
            try fileHandle?.seekToEnd()
            let marker = "\n--- Log session started at \(dateFormatter.string(from: Date())) ---\n"
            let data = Data(marker.utf8)
            try fileHandle?.write(contentsOf: data)
        } catch {
            fileHandle = nil
        }
    }

    private static func defaultLogFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cupertino")
            .appendingPathComponent("cupertino.log")
    }

    /// Log a debug message
    public static func debug(
        _ message: String,
        category: UnifiedLogger.Category = .cli
    ) {
        log(message, level: .debug, category: category)
    }

    /// Log an info message
    public static func info(
        _ message: String,
        category: UnifiedLogger.Category = .cli
    ) {
        log(message, level: .info, category: category)
    }

    /// Log a warning message
    public static func warning(
        _ message: String,
        category: UnifiedLogger.Category = .cli
    ) {
        log(message, level: .warning, category: category)
    }

    /// Log an error message
    public static func error(
        _ message: String,
        category: UnifiedLogger.Category = .cli
    ) {
        log(message, level: .error, category: category)
    }

    /// Output to console only (no logging) - for user-facing output like search results
    public static func output(_ message: String) {
        print(message)
    }

    private static func log(
        _ message: String,
        level: UnifiedLogger.Level,
        category: UnifiedLogger.Category
    ) {
        ensureInitialized()

        guard level >= options.minLevel else { return }

        // 1. Always log to os.log
        let logger = category.osLogger
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }

        // 2. Log to console if enabled
        if options.consoleEnabled {
            var output = ""
            if options.showTimestamps {
                output += "[\(dateFormatter.string(from: Date()))] "
            }
            if options.showCategory {
                output += "[\(category.rawValue)] "
            }
            output += message

            switch level {
            case .debug, .info:
                Swift.print(output)
            case .warning, .error:
                fputs("\(output)\n", stderr)
            }
        }

        // 3. Log to file if enabled
        if options.fileEnabled, let handle = fileHandle {
            let timestamp = dateFormatter.string(from: Date())
            let logLine = "[\(timestamp)] [\(level)] [\(category.rawValue)] \(message)\n"
            let data = Data(logLine.utf8)
            try? handle.write(contentsOf: data)
        }
    }
}

// MARK: - Convenience Global Functions (Async)

/// Log a debug message (async)
public func logDebug(
    _ message: String,
    category: UnifiedLogger.Category = .cli,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) async {
    await UnifiedLogger.shared.debug(message, category: category, file: file, function: function, line: line)
}

/// Log an info message (async)
public func logInfo(
    _ message: String,
    category: UnifiedLogger.Category = .cli,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) async {
    await UnifiedLogger.shared.info(message, category: category, file: file, function: function, line: line)
}

/// Log a warning message (async)
public func logWarning(
    _ message: String,
    category: UnifiedLogger.Category = .cli,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) async {
    await UnifiedLogger.shared.warning(message, category: category, file: file, function: function, line: line)
}

/// Log an error message (async)
public func logError(
    _ message: String,
    category: UnifiedLogger.Category = .cli,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) async {
    await UnifiedLogger.shared.error(message, category: category, file: file, function: function, line: line)
}
