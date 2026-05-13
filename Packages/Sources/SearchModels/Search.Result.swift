import Foundation
import SharedConstants

/// A single search result with metadata and ranking.
///
/// Lifted into SearchModels so every consumer (Services formatters,
/// MCP layer, CLI rendering) decodes + renders results without importing
/// the Search target's behavioural surface. The Search target still
/// produces values of this type; consumers stay free of the actor + DB
/// machinery that backs that production.
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
        /// BM25 score (negative, closer to zero = better match).
        public let rank: Double
        public let availability: [Search.PlatformAvailability]?
        /// AST-extracted symbols that matched the query (#81).
        public let matchedSymbols: [MatchedSymbol]?

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
            availability: [Search.PlatformAvailability]? = nil,
            matchedSymbols: [MatchedSymbol]? = nil,
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

        /// Format availability as a compact string
        /// (e.g., `"iOS 13.0+, macOS 10.15+"`).
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

        /// Get minimum iOS version (nil if not available on iOS).
        public var minimumiOS: String? {
            availability?.first { $0.name == "iOS" && !$0.unavailable }?.introducedAt
        }

        /// Get minimum macOS version (nil if not available on macOS).
        public var minimumMacOS: String? {
            availability?.first { $0.name == "macOS" && !$0.unavailable }?.introducedAt
        }

        /// Get minimum tvOS version (nil if not available on tvOS).
        public var minimumTvOS: String? {
            availability?.first { $0.name == "tvOS" && !$0.unavailable }?.introducedAt
        }

        /// Get minimum watchOS version (nil if not available on watchOS).
        public var minimumWatchOS: String? {
            availability?.first { $0.name == "watchOS" && !$0.unavailable }?.introducedAt
        }

        /// Get minimum visionOS version (nil if not available on visionOS).
        public var minimumVisionOS: String? {
            availability?.first { $0.name == "visionOS" && !$0.unavailable }?.introducedAt
        }

        /// True if `summary` was truncated from full content.
        /// Consumers can call the full-document reader to get the rest.
        public var summaryTruncated: Bool {
            // Summary ends with "..." or is close to the max length threshold.
            summary.hasSuffix("...") || summary.count >= Shared.Constants.ContentLimit.summaryMaxLength - 50
        }

        /// Summary with duplicate title lines removed (for display purposes).
        /// The content field carries the title repeated three times for BM25
        /// boosting, which may leak into `summary`.
        public var cleanedSummary: String {
            var lines = summary.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Remove consecutive duplicate lines at the start
            // (repeated titles for BM25 boosting).
            while lines.count > 1, lines[0] == lines[1] {
                lines.removeFirst()
            }
            // Remove the remaining title if it matches the document title.
            if !lines.isEmpty, lines[0] == title {
                lines.removeFirst()
            }

            return lines.joined(separator: "\n\n")
        }

        /// Inverted score (higher = better match, for easier interpretation).
        public var score: Double {
            // BM25 returns negative scores; invert for positive scores.
            -rank
        }

        // MARK: - Custom Codable (includes computed properties)

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
            availability = try container.decodeIfPresent([Search.PlatformAvailability].self, forKey: .availability)
            matchedSymbols = try container.decodeIfPresent([MatchedSymbol].self, forKey: .matchedSymbols)
            // summaryTruncated and availabilityString are computed; ignore during decode.
        }
    }
}
