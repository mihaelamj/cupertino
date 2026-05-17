import Foundation
import LoggingModels
import OSLog
import SharedConstants

// MARK: - Unified Logger

extension Logging {
    /// Unified logging system with three configurable outputs:
    /// 1. os.log (always on) - system log for debugging via `log show`
    /// 2. Console (configurable) - stdout/stderr for user feedback
    /// 3. File (optional) - for crash debugging and long-running operations
    ///
    /// **Construction.** Build one `Logging.Unified` at each binary's
    /// composition root and thread it downstream via `Logging.Composition`
    /// (preferred) or directly to `Logging.LiveRecording(unified:)`.
    ///
    /// ```swift
    /// // Composition-root construction:
    /// let logging = Logging.Composition()
    /// let recording = logging.recording  // pass into producers via init
    /// ```
    ///
    /// The legacy `Logging.Unified.shared` Singleton (GoF p. 127, rejected
    /// as Service Locator per Seemann 2011 ch. 5) was deleted in #548
    /// Phase H. There is no process-wide accessor; every consumer receives
    /// an instance via constructor injection.
    public actor Unified {
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
            case archive
            case hig

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
                case .archive: return Logging.Logger.archive
                case .hig: return Logging.Logger.hig
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

        /// Construct a `Logging.Unified` actor with the given options.
        /// Each binary's composition root builds its own instance, typically
        /// via `Logging.Composition`. Constructor injection only — there is
        /// no `.shared` accessor.
        public init(options: Options = .default) {
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
                // #682 — surface close failures via the one-shot stderr
                // warning. Calling self.error(...) here would recurse
                // back into the logger's own write path (recursive-log
                // trap); stderr-direct breaks the cycle. Same shape as
                // Search.JSONLImportLogSink's warnOnceAboutWriteFailure.
                do {
                    try handle.close()
                } catch {
                    warnOnceAboutFileHandleFailure(operation: "close (configure)", error: error)
                }
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
                // #682 — see configure() for the recursive-log rationale.
                do {
                    try handle.close()
                } catch {
                    warnOnceAboutFileHandleFailure(operation: "close (disableFileLogging)", error: error)
                }
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
            // Post-#535: no implicit fallback to Shared.Constants.defaultBaseDirectory
            // (which routed through BinaryConfig.shared — Service Locator). The
            // caller must supply an explicit fileURL via `enableFileLogging(at:)`
            // (or via the Options init) when file logging is desired. If
            // fileEnabled is true but fileURL is nil, file logging is silently
            // disabled — that's a programmer error, not a runtime fallback.
            guard let fileURL = options.fileURL else {
                fileHandle = nil
                return
            }

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
            // #682 — surface file-write failures via the one-shot stderr
            // warning. Pre-fix every per-log-message write that failed
            // (disk full, fs unmounted, handle invalidated) silently
            // dropped the log line. Now the first failure prints once
            // to stderr; subsequent writes keep trying but stay quiet
            // so a perma-broken handle doesn't spam the terminal.
            // Direct-to-stderr avoids the recursive-log trap that would
            // happen if we called self.error(...) from inside the
            // logger's own write path.
            if let handle = fileHandle {
                do {
                    try handle.write(contentsOf: data)
                } catch {
                    warnOnceAboutFileHandleFailure(operation: "write", error: error)
                }
            }
        }

        // MARK: - Cleanup

        deinit {
            // Note: This won't be called for actors, but keeping for documentation
        }

        /// Flush and close the log file
        public func close() {
            if let handle = fileHandle {
                // #682 — surface synchronize / close failures via the
                // one-shot stderr warning. See configure() / write
                // sites above for the recursive-log rationale.
                do {
                    try handle.synchronize()
                } catch {
                    warnOnceAboutFileHandleFailure(operation: "synchronize (close)", error: error)
                }
                do {
                    try handle.close()
                } catch {
                    warnOnceAboutFileHandleFailure(operation: "close", error: error)
                }
                fileHandle = nil
            }
        }

        // MARK: - #682 — one-shot stderr warning for file-handle failures

        /// One-shot flag so a broken disk / closed file surfaces ONCE on
        /// stderr instead of either silently losing every log entry
        /// (the pre-#682 try? behaviour) or spamming the terminal with
        /// a warning per row. After the first warning the logger keeps
        /// trying to write (next write may succeed; we don't know what
        /// state the FS is in) but stays quiet about repeated failures.
        ///
        /// Same shape as `Search.JSONLImportLogSink.warnOnceAboutWriteFailure`
        /// (develop's #681 fix), generalised to cover every file-handle
        /// operation in this actor (write / close / synchronize). The
        /// `operation` parameter names which one failed so a postmortem
        /// can distinguish "log writes started failing mid-run" from
        /// "couldn't even close the file at shutdown".
        ///
        /// Writes go to `FileHandle.standardError` directly — calling
        /// `self.error(...)` would recurse into this same write path
        /// (the recursive-log trap), so we break the cycle by going
        /// straight to stderr.
        private var hasWarnedAboutFileHandleFailure = false

        private func warnOnceAboutFileHandleFailure(operation: String, error: Swift.Error) {
            guard !hasWarnedAboutFileHandleFailure else { return }
            hasWarnedAboutFileHandleFailure = true
            let path = options.fileURL?.path ?? "(unknown path)"
            let message = "⚠️  Logging.Unified \(operation) failure on \(path): " +
                "\(error). Subsequent failures will be silent; the file log may be incomplete.\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }
}

// closes extension Logging (Unified)
