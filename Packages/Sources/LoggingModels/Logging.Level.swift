import Foundation

// MARK: - Logging.Level

extension Logging {
    /// Severity levels carried alongside every log record. Comparable
    /// so a `Recording` can short-circuit on a minimum-level threshold
    /// without consulting an external filter.
    public enum Level: Int, Sendable, Comparable, CustomStringConvertible {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        public static func < (lhs: Level, rhs: Level) -> Bool {
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
    }
}
