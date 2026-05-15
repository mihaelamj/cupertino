import Foundation
// MARK: - Crawl Metadata

/// Metadata tracking crawl state and statistics
extension Shared.Models {
    public struct CrawlMetadata: Codable, Sendable {
        public var pages: [String: PageMetadata] // URL -> metadata
        public var frameworks: [String: FrameworkStats] // framework name -> stats
        public var lastCrawl: Date?
        public var stats: CrawlStatistics
        public var crawlState: CrawlSessionState? // Resume state

        public init(
            pages: [String: PageMetadata] = [:],
            frameworks: [String: FrameworkStats] = [:],
            lastCrawl: Date? = nil,
            stats: CrawlStatistics = CrawlStatistics(),
            crawlState: CrawlSessionState? = nil
        ) {
            self.pages = pages
            self.frameworks = frameworks
            self.lastCrawl = lastCrawl
            self.stats = stats
            self.crawlState = crawlState
        }

        /// Save metadata to file
        public func save(to url: URL) throws {
            try Shared.Utils.JSONCoding.encode(self, to: url)
        }

        /// Load metadata from file
        public static func load(from url: URL) throws -> CrawlMetadata {
            try Shared.Utils.JSONCoding.decode(CrawlMetadata.self, from: url)
        }

        /// Get statistics grouped by framework
        public func statsByFramework() -> [String: FrameworkStats] {
            // If frameworks dict is populated, return it
            if !frameworks.isEmpty {
                return frameworks
            }

            // Otherwise compute from pages
            var stats: [String: FrameworkStats] = [:]
            for (_, page) in pages {
                let framework = page.framework.lowercased()
                if var existing = stats[framework] {
                    existing.pageCount += 1
                    existing.lastCrawled = max(existing.lastCrawled ?? .distantPast, page.lastCrawled)
                    stats[framework] = existing
                } else {
                    stats[framework] = FrameworkStats(
                        name: page.framework,
                        pageCount: 1,
                        lastCrawled: page.lastCrawled
                    )
                }
            }
            return stats
        }

        // MARK: - Codable

        /// Custom decoder to handle missing fields in old metadata files
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Decode with defaults for missing fields
            pages = try container.decodeIfPresent([String: PageMetadata].self, forKey: .pages) ?? [:]
            frameworks = try container.decodeIfPresent([String: FrameworkStats].self, forKey: .frameworks) ?? [:]
            lastCrawl = try container.decodeIfPresent(Date.self, forKey: .lastCrawl)
            stats = try container.decodeIfPresent(CrawlStatistics.self, forKey: .stats) ?? CrawlStatistics()
            crawlState = try container.decodeIfPresent(CrawlSessionState.self, forKey: .crawlState)
        }

        private enum CodingKeys: String, CodingKey {
            case pages, frameworks, lastCrawl, stats, crawlState
        }
    }
}

// MARK: - Framework Stats

/// Statistics for a single framework
extension Shared.Models {
    public struct FrameworkStats: Codable, Sendable {
        public var name: String
        public var pageCount: Int
        public var newPages: Int
        public var updatedPages: Int
        public var errors: Int
        public var lastCrawled: Date?
        public var crawlStatus: CrawlStatus

        public enum CrawlStatus: String, Codable, Sendable {
            case notStarted = "not_started"
            case inProgress = "in_progress"
            case complete
            case partial
            case failed
        }

        public init(
            name: String,
            pageCount: Int = 0,
            newPages: Int = 0,
            updatedPages: Int = 0,
            errors: Int = 0,
            lastCrawled: Date? = nil,
            crawlStatus: CrawlStatus = .notStarted
        ) {
            self.name = name
            self.pageCount = pageCount
            self.newPages = newPages
            self.updatedPages = updatedPages
            self.errors = errors
            self.lastCrawled = lastCrawled
            self.crawlStatus = crawlStatus
        }

        // MARK: - Codable

        /// Custom decoder to handle missing fields in old metadata files
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Provide defaults for missing fields
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 0
            newPages = try container.decodeIfPresent(Int.self, forKey: .newPages) ?? 0
            updatedPages = try container.decodeIfPresent(Int.self, forKey: .updatedPages) ?? 0
            errors = try container.decodeIfPresent(Int.self, forKey: .errors) ?? 0
            lastCrawled = try container.decodeIfPresent(Date.self, forKey: .lastCrawled)
            crawlStatus = try container.decodeIfPresent(CrawlStatus.self, forKey: .crawlStatus) ?? .notStarted
        }

        private enum CodingKeys: String, CodingKey {
            case name, pageCount, newPages, updatedPages, errors, lastCrawled, crawlStatus
        }
    }
}

// MARK: - Page Metadata

/// Metadata for a single crawled page
extension Shared.Models {
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

        // MARK: - Codable

        /// Custom decoder to handle missing fields in old metadata files
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Provide defaults for missing fields
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            framework = try container.decodeIfPresent(String.self, forKey: .framework) ?? "unknown"
            filePath = try container.decodeIfPresent(String.self, forKey: .filePath) ?? ""
            contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash) ?? ""
            depth = try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0
            lastCrawled = try container.decodeIfPresent(Date.self, forKey: .lastCrawled) ?? Date()
        }

        private enum CodingKeys: String, CodingKey {
            case url, framework, filePath, contentHash, depth, lastCrawled
        }
    }
}

// MARK: - Crawl Statistics

/// Statistics for a crawl session
extension Shared.Models {
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

        // MARK: - Codable

        /// Custom decoder to handle missing fields in old metadata files
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Provide defaults for missing fields
            totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
            newPages = try container.decodeIfPresent(Int.self, forKey: .newPages) ?? 0
            updatedPages = try container.decodeIfPresent(Int.self, forKey: .updatedPages) ?? 0
            skippedPages = try container.decodeIfPresent(Int.self, forKey: .skippedPages) ?? 0
            errors = try container.decodeIfPresent(Int.self, forKey: .errors) ?? 0
            startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
            endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        }

        private enum CodingKeys: String, CodingKey {
            case totalPages, newPages, updatedPages, skippedPages, errors, startTime, endTime
        }
    }
}

// MARK: - Crawl Session State

/// Represents the complete state of a crawl session for resuming
extension Shared.Models {
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
}

/// Represents a URL in the crawl queue with depth information
extension Shared.Models {
    public struct QueuedURL: Codable, Sendable, Hashable {
        public let url: String
        public let depth: Int

        public init(url: String, depth: Int) {
            self.url = url
            self.depth = depth
        }
    }
}
