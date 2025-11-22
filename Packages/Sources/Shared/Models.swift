import CryptoKit
import Foundation

// MARK: - Documentation Page

/// Represents a single documentation page
public struct DocumentationPage: Codable, Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let framework: String
    public let title: String
    public let filePath: URL
    public let contentHash: String
    public let depth: Int
    public let lastCrawled: Date

    public init(
        id: UUID = UUID(),
        url: URL,
        framework: String,
        title: String,
        filePath: URL,
        contentHash: String,
        depth: Int,
        lastCrawled: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.framework = framework
        self.title = title
        self.filePath = filePath
        self.contentHash = contentHash
        self.depth = depth
        self.lastCrawled = lastCrawled
    }
}

// MARK: - Crawl Metadata

/// Metadata tracking crawl state and statistics
public struct CrawlMetadata: Codable, Sendable {
    public var pages: [String: PageMetadata] // URL -> metadata
    public var lastCrawl: Date?
    public var stats: CrawlStatistics
    public var crawlState: CrawlSessionState? // Resume state

    public init(
        pages: [String: PageMetadata] = [:],
        lastCrawl: Date? = nil,
        stats: CrawlStatistics = CrawlStatistics(),
        crawlState: CrawlSessionState? = nil
    ) {
        self.pages = pages
        self.lastCrawl = lastCrawl
        self.stats = stats
        self.crawlState = crawlState
    }

    /// Save metadata to file
    public func save(to url: URL) throws {
        try JSONCoding.encode(self, to: url)
    }

    /// Load metadata from file
    public static func load(from url: URL) throws -> CrawlMetadata {
        try JSONCoding.decode(CrawlMetadata.self, from: url)
    }
}

// MARK: - Page Metadata

/// Metadata for a single crawled page
public struct PageMetadata: Codable, Sendable {
    public let url: String
    public let framework: String
    public let filePath: String
    public let contentHash: String
    public let depth: Int
    public let lastCrawled: Date

    public init(
        url: String,
        framework: String,
        filePath: String,
        contentHash: String,
        depth: Int,
        lastCrawled: Date = Date()
    ) {
        self.url = url
        self.framework = framework
        self.filePath = filePath
        self.contentHash = contentHash
        self.depth = depth
        self.lastCrawled = lastCrawled
    }
}

// MARK: - Crawl Statistics

/// Statistics for a crawl session
public struct CrawlStatistics: Codable, Sendable {
    public var totalPages: Int
    public var newPages: Int
    public var updatedPages: Int
    public var skippedPages: Int
    public var errors: Int
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalPages: Int = 0,
        newPages: Int = 0,
        updatedPages: Int = 0,
        skippedPages: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalPages = totalPages
        self.newPages = newPages
        self.updatedPages = updatedPages
        self.skippedPages = skippedPages
        self.errors = errors
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Duration of the crawl in seconds
    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else {
            return nil
        }
        return end.timeIntervalSince(start)
    }
}

// MARK: - Hash Utilities

/// Utilities for content hashing
public enum HashUtilities {
    /// Compute SHA-256 hash of a string
    public static func sha256(of string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Compute SHA-256 hash of data
    public static func sha256(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - URL Utilities

/// Utilities for URL manipulation
public enum URLUtilities {
    /// Normalize a URL (remove hash, query params)
    public static func normalize(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.query = nil
        return components?.url
    }

    /// Extract framework name from documentation URL (Apple or Swift.org)
    public static func extractFramework(from url: URL) -> String {
        let pathComponents = url.pathComponents

        // Handle docs.swift.org URLs (e.g., /swift-book/documentation/the-swift-programming-language/*)
        if url.host?.contains(Shared.Constants.HostDomain.swiftOrg) == true {
            if pathComponents.contains(Shared.Constants.PathComponent.swiftBook) {
                return Shared.Constants.PathComponent.swiftBook
            }
            return Shared.Constants.PathComponent.swiftOrgFramework
        }

        // Handle developer.apple.com URLs (e.g., /documentation/swiftui/*)
        if let docIndex = pathComponents.firstIndex(of: "documentation"),
           docIndex + 1 < pathComponents.count {
            return pathComponents[docIndex + 1].lowercased()
        }

        return "root"
    }

    /// Generate filename from URL
    public static func filename(from url: URL) -> String {
        var cleaned = url.absoluteString

        // Remove known domain prefixes
        cleaned = cleaned
            .replacingOccurrences(of: "\(Shared.Constants.BaseURL.appleDeveloper)/", with: "")
            .replacingOccurrences(of: "\(Shared.Constants.BaseURL.swiftOrg)", with: "")
            .replacingOccurrences(of: Shared.Constants.URLCleanupPattern.swiftOrgWWW, with: "")

        // Normalize to safe filename
        cleaned = cleaned
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "^_+|_+$", with: "", options: .regularExpression)

        return cleaned.isEmpty ? "index" : cleaned
    }
}

// MARK: - Crawl Session State

/// Represents the complete state of a crawl session for resuming
public struct CrawlSessionState: Codable, Sendable {
    public var visited: Set<String> // Visited URL strings
    public var queue: [QueuedURL] // Pending URLs to crawl
    public var startURL: String
    public var outputDirectory: String // Where files are being saved
    public var sessionStartTime: Date
    public var lastSaveTime: Date
    public var isActive: Bool

    public init(
        visited: Set<String> = [],
        queue: [QueuedURL] = [],
        startURL: String,
        outputDirectory: String,
        sessionStartTime: Date = Date(),
        lastSaveTime: Date = Date(),
        isActive: Bool = true
    ) {
        self.visited = visited
        self.queue = queue
        self.startURL = startURL
        self.outputDirectory = outputDirectory
        self.sessionStartTime = sessionStartTime
        self.lastSaveTime = lastSaveTime
        self.isActive = isActive
    }
}

/// Represents a URL in the crawl queue with depth information
public struct QueuedURL: Codable, Sendable, Hashable {
    public let url: String
    public let depth: Int

    public init(url: String, depth: Int) {
        self.url = url
        self.depth = depth
    }
}

// MARK: - Package Documentation Models

/// Reference to a Swift package for documentation download
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

/// Priority level for package documentation
public enum PackagePriority: String, Codable, Sendable {
    case appleOfficial
    case ecosystem
    case community
}

/// Detected documentation site for a package
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

/// Progress information for package documentation downloads
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

/// Statistics for package documentation downloads
public struct PackageDownloadStatistics: Sendable {
    public var totalPackages: Int
    public var newREADMEs: Int
    public var updatedREADMEs: Int
    public var successfulDocs: Int
    public var errors: Int
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalPackages: Int = 0,
        newREADMEs: Int = 0,
        updatedREADMEs: Int = 0,
        successfulDocs: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalPackages = totalPackages
        self.newREADMEs = newREADMEs
        self.updatedREADMEs = updatedREADMEs
        self.successfulDocs = successfulDocs
        self.errors = errors
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Total successful READMEs (new + updated)
    public var successfulREADMEs: Int {
        newREADMEs + updatedREADMEs
    }

    /// Duration of the download in seconds
    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else {
            return nil
        }
        return end.timeIntervalSince(start)
    }
}
