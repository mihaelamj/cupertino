import Foundation
import SharedConstants

// MARK: - Package Documentation Models

/// Reference to a Swift package for documentation download
extension Shared.Models {
    public struct PackageReference: Codable, Sendable, Hashable {
        public let owner: String
        public let repo: String
        public let url: String
        public let priority: PackagePriority

        public init(owner: String, repo: String, url: String, priority: PackagePriority) {
            self.owner = owner
            self.repo = repo
            self.url = url
            self.priority = priority
        }
    }
}

/// Priority level for package documentation
extension Shared.Models {
    public enum PackagePriority: String, Codable, Sendable {
        case appleOfficial
        case ecosystem
        case community
    }
}

/// Detected documentation site for a package
extension Shared.Models {
    public struct DocumentationSite: Codable, Sendable, Hashable {
        public let type: DocumentationType
        public let baseURL: URL

        public init(type: DocumentationType, baseURL: URL) {
            self.type = type
            self.baseURL = baseURL
        }

        /// Type of documentation site
        public enum DocumentationType: String, Codable, Sendable {
            case githubPages
            case customDomain
            case githubWiki
            case readmeOnly
        }
    }
}

/// Progress information for package documentation downloads
extension Shared.Models {
    public struct PackageDownloadProgress: Sendable {
        public let currentPackage: String
        public let completed: Int
        public let total: Int
        public let status: String

        public init(currentPackage: String, completed: Int, total: Int, status: String) {
            self.currentPackage = currentPackage
            self.completed = completed
            self.total = total
            self.status = status
        }

        /// Progress percentage (0-100)
        public var percentage: Double {
            guard total > 0 else { return 0 }
            return (Double(completed) / Double(total)) * 100.0
        }
    }
}

/// Statistics for package documentation downloads
extension Shared.Models {
    public struct PackageDownloadStatistics: Sendable {
        public var totalPackages: Int
        public var newPackages: Int
        public var updatedPackages: Int
        public var totalFilesSaved: Int
        public var totalBytesSaved: Int64
        public var successfulDocs: Int
        public var errors: Int
        public var startTime: Date?
        public var endTime: Date?

        public init(
            totalPackages: Int = 0,
            newPackages: Int = 0,
            updatedPackages: Int = 0,
            totalFilesSaved: Int = 0,
            totalBytesSaved: Int64 = 0,
            successfulDocs: Int = 0,
            errors: Int = 0,
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.totalPackages = totalPackages
            self.newPackages = newPackages
            self.updatedPackages = updatedPackages
            self.totalFilesSaved = totalFilesSaved
            self.totalBytesSaved = totalBytesSaved
            self.successfulDocs = successfulDocs
            self.errors = errors
            self.startTime = startTime
            self.endTime = endTime
        }

        /// Total successful packages (new + updated)
        public var successfulPackages: Int {
            newPackages + updatedPackages
        }

        /// Duration of the download in seconds
        public var duration: TimeInterval? {
            guard let start = startTime, let end = endTime else {
                return nil
            }
            return end.timeIntervalSince(start)
        }
    }
}
