import Foundation
import SharedConstants

// MARK: - Sample Index Errors

/// Lifted from `Packages/Sources/SampleIndex/Sample.Index.Error.swift` to
/// this foundation-only target by #902 (mirror of the #898 sub-PR E
/// Search.Error lift) so both the orchestration `SampleIndex` target and
/// the SQLite-backed `SampleIndexSQLite` concrete can throw and catch
/// `Sample.Index.Error` without depending on each other.
extension Sample.Index {
    /// Errors that can occur during sample code indexing and search
    public enum Error: Swift.Error, LocalizedError, Sendable {
        case databaseNotInitialized
        case sqliteError(String)
        case prepareFailed(String)
        case insertFailed(String)
        case searchFailed(String)
        case invalidQuery(String)
        case zipExtractionFailed(String)
        case projectNotFound(String)
        case fileNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .databaseNotInitialized:
                return "Sample index database not initialized"
            case let .sqliteError(message):
                return "SQLite error: \(message)"
            case let .prepareFailed(message):
                return "Statement prepare failed: \(message)"
            case let .insertFailed(message):
                return "Insert failed: \(message)"
            case let .searchFailed(message):
                return "Search failed: \(message)"
            case let .invalidQuery(message):
                return "Invalid query: \(message)"
            case let .zipExtractionFailed(message):
                return "ZIP extraction failed: \(message)"
            case let .projectNotFound(id):
                return "Project not found: \(id)"
            case let .fileNotFound(path):
                return "File not found: \(path)"
            }
        }
    }
}
