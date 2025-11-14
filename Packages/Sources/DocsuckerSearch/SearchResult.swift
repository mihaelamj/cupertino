import Foundation

// MARK: - Search Result

/// A single search result with metadata and ranking
public struct SearchResult: Codable, Sendable, Identifiable {
    public let id: UUID
    public let uri: String
    public let framework: String
    public let title: String
    public let summary: String
    public let filePath: String
    public let wordCount: Int
    public let rank: Double // BM25 score (negative, closer to 0 = better match)

    public init(
        id: UUID = UUID(),
        uri: String,
        framework: String,
        title: String,
        summary: String,
        filePath: String,
        wordCount: Int,
        rank: Double
    ) {
        self.id = id
        self.uri = uri
        self.framework = framework
        self.title = title
        self.summary = summary
        self.filePath = filePath
        self.wordCount = wordCount
        self.rank = rank
    }

    /// Inverted score (higher = better match, for easier interpretation)
    public var score: Double {
        // BM25 returns negative scores, invert for positive scores
        return -rank
    }
}

// MARK: - Search Errors

public enum SearchError: Error, LocalizedError {
    case databaseNotInitialized
    case sqliteError(String)
    case prepareFailed(String)
    case insertFailed(String)
    case searchFailed(String)
    case invalidQuery(String)

    public var errorDescription: String? {
        switch self {
        case .databaseNotInitialized:
            return "Search database has not been initialized. Run 'docsucker build-index' first."
        case .sqliteError(let msg):
            return "SQLite error: \(msg)"
        case .prepareFailed(let msg):
            return "Failed to prepare SQL statement: \(msg)"
        case .insertFailed(let msg):
            return "Failed to insert document: \(msg)"
        case .searchFailed(let msg):
            return "Search query failed: \(msg)"
        case .invalidQuery(let msg):
            return "Invalid search query: \(msg)"
        }
    }
}
