import Foundation
import SearchModels
import SharedConstants

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

// `Search.Error` lives in `SearchModels.Search.Error` (foundation seam) so
// both this orchestration target and the SearchSQLite concrete (and any
// future backend) can throw + catch it without depending on each other.
