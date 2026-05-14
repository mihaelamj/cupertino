import Foundation

// MARK: - Logging.Recording

extension Logging {
    /// GoF Strategy (1994 p. 315) seam for log-record emission. Each
    /// consumer takes `any Logging.Recording` as a constructor parameter
    /// or method argument; the binary supplies the concrete recorder
    /// at the composition root.
    ///
    /// Replaces the `Logging.Log` static surface, `Logging.ConsoleLogger`
    /// static helpers, and the `Logging.Unified.shared` actor singleton.
    /// Those three were Service Locators (Seemann, *Dependency
    /// Injection*, 2011, ch. 5): consumers reached for a module-scope
    /// shared instance instead of receiving one.
    ///
    /// Concrete production conformer is `Logging.LiveRecording` (in the
    /// `Logging` target, wraps OSLog + console + optional file output).
    /// Test conformer is `Logging.NoopRecording` (in this target —
    /// foundation-only so test bundles can take a test-shaped recorder
    /// without importing the concrete writer surface).
    public protocol Recording: Sendable {
        /// Record a message at the given level + category.
        func record(_ message: String, level: Level, category: Category)

        /// Print a single line to stdout with no decoration. Kept on the
        /// protocol so callers that want user-facing output (search
        /// results, doctor output, JSON dumps) flow through the same
        /// recorder as logs and tests can capture them together.
        func output(_ message: String)
    }
}

// MARK: - Convenience methods (free, level-specific)

extension Logging.Recording {
    public func debug(_ message: String, category: Logging.Category = .cli) {
        record(message, level: .debug, category: category)
    }

    public func info(_ message: String, category: Logging.Category = .cli) {
        record(message, level: .info, category: category)
    }

    public func warning(_ message: String, category: Logging.Category = .cli) {
        record(message, level: .warning, category: category)
    }

    public func error(_ message: String, category: Logging.Category = .cli) {
        record(message, level: .error, category: category)
    }
}
