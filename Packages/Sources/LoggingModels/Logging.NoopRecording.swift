import Foundation

// MARK: - Logging.NoopRecording

extension Logging {
    /// Inert `Recording` conformer that drops every record. Used by tests
    /// that need to satisfy a `logger:` parameter without coupling to
    /// the OSLog + console + file behaviour of `Logging.LiveRecording`.
    ///
    /// Parallel to the test stubs in `CrawlerModels.NoopStrategies` and
    /// the `Sample.Index.DatabaseFactory` test doubles in
    /// `Tests/ServicesTests` — protocol-typed seam, no I/O, no shared
    /// state. Safe to construct in any concurrency context.
    public struct NoopRecording: Recording {
        public init() {}

        public func record(_ message: String, level: Level, category: Category) {
            _ = (message, level, category)
        }

        public func output(_ message: String) {
            _ = message
        }
    }
}
