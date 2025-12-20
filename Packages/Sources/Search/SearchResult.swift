import Foundation
import Shared

// MARK: - Framework Availability (Search Module)

/// Minimum platform versions for a framework (used for availability filtering)
public struct FrameworkAvailability: Sendable {
    public let minIOS: String?
    public let minMacOS: String?
    public let minTvOS: String?
    public let minWatchOS: String?
    public let minVisionOS: String?

    public init(
        minIOS: String? = nil,
        minMacOS: String? = nil,
        minTvOS: String? = nil,
        minWatchOS: String? = nil,
        minVisionOS: String? = nil
    ) {
        self.minIOS = minIOS
        self.minMacOS = minMacOS
        self.minTvOS = minTvOS
        self.minWatchOS = minWatchOS
        self.minVisionOS = minVisionOS
    }

    /// Empty availability (no platform data)
    public static let empty = FrameworkAvailability()
}

// MARK: - Platform Availability (Search Module)

/// Lightweight platform availability for search results
public struct SearchPlatformAvailability: Codable, Sendable, Hashable {
    public let name: String
    public let introducedAt: String?
    public let deprecated: Bool
    public let unavailable: Bool
    public let beta: Bool

    public init(
        name: String,
        introducedAt: String? = nil,
        deprecated: Bool = false,
        unavailable: Bool = false,
        beta: Bool = false
    ) {
        self.name = name
        self.introducedAt = introducedAt
        self.deprecated = deprecated
        self.unavailable = unavailable
        self.beta = beta
    }
}

// MARK: - Matched Symbol

/// A symbol extracted from documentation that matched the search query
public struct MatchedSymbol: Codable, Sendable, Hashable {
    public let kind: String // struct, class, actor, enum, protocol, function, property, etc.
    public let name: String
    public let signature: String? // Full signature for functions/methods
    public let isAsync: Bool

    public init(kind: String, name: String, signature: String? = nil, isAsync: Bool = false) {
        self.kind = kind
        self.name = name
        self.signature = signature
        self.isAsync = isAsync
    }

    /// Compact display format (e.g., "class UIFontMetrics" or "func scaledFont(for:)")
    public var displayString: String {
        if let sig = signature, !sig.isEmpty {
            return "\(kind) \(sig)"
        }
        return "\(kind) \(name)"
    }
}

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
        public let availability: [SearchPlatformAvailability]?
        public let matchedSymbols: [MatchedSymbol]? // AST-extracted symbols that matched query (#81)

        public init(
            id: UUID = UUID(),
            uri: String,
            source: String,
            framework: String,
            title: String,
            summary: String,
            filePath: String,
            wordCount: Int,
            rank: Double,
            availability: [SearchPlatformAvailability]? = nil,
            matchedSymbols: [MatchedSymbol]? = nil
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
            self.availability = availability
            self.matchedSymbols = matchedSymbols
        }

        /// Format availability as a compact string (e.g., "iOS 13.0+, macOS 10.15+")
        public var availabilityString: String? {
            guard let availability, !availability.isEmpty else { return nil }
            return availability
                .filter { !$0.unavailable }
                .compactMap { platform -> String? in
                    guard let version = platform.introducedAt else { return nil }
                    var str = "\(platform.name) \(version)+"
                    if platform.deprecated {
                        str += " (deprecated)"
                    }
                    if platform.beta {
                        str += " (beta)"
                    }
                    return str
                }
                .joined(separator: ", ")
        }

        /// Get minimum iOS version (nil if not available on iOS)
        public var minimumiOS: String? {
            availability?.first { $0.name == "iOS" && !$0.unavailable }?.introducedAt
        }

        /// Get minimum macOS version (nil if not available on macOS)
        public var minimumMacOS: String? {
            availability?.first { $0.name == "macOS" && !$0.unavailable }?.introducedAt
        }

        /// Get minimum tvOS version (nil if not available on tvOS)
        public var minimumTvOS: String? {
            availability?.first { $0.name == "tvOS" && !$0.unavailable }?.introducedAt
        }

        /// Get minimum watchOS version (nil if not available on watchOS)
        public var minimumWatchOS: String? {
            availability?.first { $0.name == "watchOS" && !$0.unavailable }?.introducedAt
        }

        /// Get minimum visionOS version (nil if not available on visionOS)
        public var minimumVisionOS: String? {
            availability?.first { $0.name == "visionOS" && !$0.unavailable }?.introducedAt
        }

        /// True if summary was truncated from full content (use read_document to get full content)
        public var summaryTruncated: Bool {
            // Summary ends with "..." or is close to the max length threshold
            summary.hasSuffix("...") || summary.count >= Shared.Constants.ContentLimit.summaryMaxLength - 50
        }

        /// Summary with duplicate title lines removed (for display purposes)
        /// The content field has title repeated 3x for BM25 boosting, which may leak into summary
        public var cleanedSummary: String {
            // Filter out empty lines and trim each line
            var lines = summary.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Remove consecutive duplicate lines at the start (repeated titles for BM25 boosting)
            while lines.count > 1, lines[0] == lines[1] {
                lines.removeFirst()
            }
            // Remove the remaining title if it matches the document title
            if !lines.isEmpty, lines[0] == title {
                lines.removeFirst()
            }

            return lines.joined(separator: "\n\n")
        }

        /// Inverted score (higher = better match, for easier interpretation)
        public var score: Double {
            // BM25 returns negative scores, invert for positive scores
            -rank
        }

        // MARK: - Custom Codable (include computed properties)

        private enum CodingKeys: String, CodingKey {
            case id, uri, source, framework, title, summary, filePath, wordCount, rank
            case summaryTruncated, availability, availabilityString, matchedSymbols
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(uri, forKey: .uri)
            try container.encode(source, forKey: .source)
            try container.encode(framework, forKey: .framework)
            try container.encode(title, forKey: .title)
            try container.encode(cleanedSummary, forKey: .summary)
            try container.encode(filePath, forKey: .filePath)
            try container.encode(wordCount, forKey: .wordCount)
            try container.encode(rank, forKey: .rank)
            try container.encode(summaryTruncated, forKey: .summaryTruncated)
            try container.encodeIfPresent(availability, forKey: .availability)
            try container.encodeIfPresent(availabilityString, forKey: .availabilityString)
            try container.encodeIfPresent(matchedSymbols, forKey: .matchedSymbols)
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
            availability = try container.decodeIfPresent([SearchPlatformAvailability].self, forKey: .availability)
            matchedSymbols = try container.decodeIfPresent([MatchedSymbol].self, forKey: .matchedSymbols)
            // summaryTruncated and availabilityString are computed, ignore during decode
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
