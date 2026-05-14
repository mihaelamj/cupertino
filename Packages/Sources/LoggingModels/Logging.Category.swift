import Foundation

// MARK: - Logging.Category

extension Logging {
    /// Subsystem categories carried alongside every log record. Each
    /// concrete `Logging.Recording` decides what to do with the category
    /// (Apple OSLog uses it for `os.Logger(subsystem:category:)`; a
    /// console-only test stub may stringify it as a tag).
    ///
    /// Public + raw-Stringly so test stubs can compare against a known
    /// set of categories without importing the concrete `Logging` target.
    public enum Category: String, Sendable, CaseIterable {
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
    }
}
