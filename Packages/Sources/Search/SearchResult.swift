import Foundation
import Shared

// MARK: - Search Result

/// A single search result with metadata and ranking
extension Search {
    public struct Result: Codable, Sendable, Identifiable {
        public let id: UUID
        public let uri: String
        public let source: String
        public let framework: String
        public let title: String
        public let summary: String
        public let filePath: String
        public let wordCount: Int
        public let rank: Double // BM25 score (negative, closer to 0 = better match)

        public init(
            id: UUID = UUID(),
            uri: String,
            source: String,
            framework: String,
            title: String,
            summary: String,
            filePath: String,
            wordCount: Int,
            rank: Double
        ) {
            self.id = id
            self.uri = uri
            self.source = source
            self.framework = framework
            self.title = title
            self.summary = summary
            self.filePath = filePath
            self.wordCount = wordCount
            self.rank = rank
        }

        /// True if summary was truncated from full content (use read_document to get full content)
        public var summaryTruncated: Bool {
            // Summary ends with "..." or is close to the max length threshold
            summary.hasSuffix("...") || summary.count >= Shared.Constants.ContentLimit.summaryMaxLength - 50
        }

        /// Inverted score (higher = better match, for easier interpretation)
        public var score: Double {
            // BM25 returns negative scores, invert for positive scores
            -rank
        }

        // MARK: - Custom Codable (include computed properties)

        private enum CodingKeys: String, CodingKey {
            case id, uri, source, framework, title, summary, filePath, wordCount, rank, summaryTruncated
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(uri, forKey: .uri)
            try container.encode(source, forKey: .source)
            try container.encode(framework, forKey: .framework)
            try container.encode(title, forKey: .title)
            try container.encode(summary, forKey: .summary)
            try container.encode(filePath, forKey: .filePath)
            try container.encode(wordCount, forKey: .wordCount)
            try container.encode(rank, forKey: .rank)
            try container.encode(summaryTruncated, forKey: .summaryTruncated)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            uri = try container.decode(String.self, forKey: .uri)
            source = try container.decode(String.self, forKey: .source)
            framework = try container.decode(String.self, forKey: .framework)
            title = try container.decode(String.self, forKey: .title)
            summary = try container.decode(String.self, forKey: .summary)
            filePath = try container.decode(String.self, forKey: .filePath)
            wordCount = try container.decode(Int.self, forKey: .wordCount)
            rank = try container.decode(Double.self, forKey: .rank)
            // summaryTruncated is computed, ignore during decode
        }
    }
}

// MARK: - Sample Code Search Result

/// A sample code search result with metadata and local file information
extension Search {
    public struct SampleCodeResult: Codable, Sendable, Identifiable {
        public let id: UUID
        public let url: String
        public let framework: String
        public let title: String
        public let description: String
        public let zipFilename: String
        public let webURL: String
        public let localPath: String?
        public let hasLocalFile: Bool
        public let rank: Double // BM25 score (negative, closer to 0 = better match)

        public init(
            id: UUID = UUID(),
            url: String,
            framework: String,
            title: String,
            description: String,
            zipFilename: String,
            webURL: String,
            localPath: String? = nil,
            hasLocalFile: Bool = false,
            rank: Double
        ) {
            self.id = id
            self.url = url
            self.framework = framework
            self.title = title
            self.description = description
            self.zipFilename = zipFilename
            self.webURL = webURL
            self.localPath = localPath
            self.hasLocalFile = hasLocalFile
            self.rank = rank
        }

        /// Inverted score (higher = better match, for easier interpretation)
        public var score: Double {
            -rank
        }

        /// Get the download URL - prefers local file:// if available, otherwise web URL
        public var downloadURL: String {
            if let localPath {
                return "file://\(localPath)"
            }
            return webURL
        }
    }
}

// MARK: - Package Search Result

/// A Swift package search result with metadata
extension Search {
    public struct PackageResult: Codable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let owner: String
        public let repositoryURL: String
        public let documentationURL: String?
        public let stars: Int
        public let isAppleOfficial: Bool
        public let description: String?

        public init(
            id: Int,
            name: String,
            owner: String,
            repositoryURL: String,
            documentationURL: String? = nil,
            stars: Int,
            isAppleOfficial: Bool,
            description: String? = nil
        ) {
            self.id = id
            self.name = name
            self.owner = owner
            self.repositoryURL = repositoryURL
            self.documentationURL = documentationURL
            self.stars = stars
            self.isAppleOfficial = isAppleOfficial
            self.description = description
        }
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
            return "Search database has not been initialized. Run 'cupertino build-index' first."
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
