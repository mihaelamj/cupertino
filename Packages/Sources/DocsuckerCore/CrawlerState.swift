import Foundation
import DocsuckerShared

// MARK: - Crawler State Manager

/// Manages crawler state including metadata and change detection
public actor CrawlerState {
    private let configuration: ChangeDetectionConfiguration
    private var metadata: CrawlMetadata

    public init(configuration: ChangeDetectionConfiguration) {
        self.configuration = configuration
        self.metadata = CrawlMetadata()

        // Load existing metadata if available
        if FileManager.default.fileExists(atPath: configuration.metadataFile.path) {
            do {
                self.metadata = try CrawlMetadata.load(from: configuration.metadataFile)
            } catch {
                print("⚠️  Failed to load metadata: \(error.localizedDescription)")
                print("   Starting with fresh metadata")
            }
        }
    }

    // MARK: - Change Detection

    /// Check if a page should be recrawled
    public func shouldRecrawl(url: String, contentHash: String, filePath: URL) -> Bool {
        // Force recrawl if configured
        if configuration.forceRecrawl {
            return true
        }

        // Always crawl if change detection is disabled
        if !configuration.enabled {
            return true
        }

        // Check if we have metadata for this URL
        guard let pageMetadata = metadata.pages[url] else {
            return true // New page, need to crawl
        }

        // Check if content hash changed
        if pageMetadata.contentHash != contentHash {
            return true // Content changed
        }

        // Check if file still exists
        if !FileManager.default.fileExists(atPath: filePath.path) {
            return true // File missing, need to recreate
        }

        return false // No changes, skip
    }

    // MARK: - Metadata Management

    /// Update metadata for a crawled page
    public func updatePage(
        url: String,
        framework: String,
        filePath: String,
        contentHash: String,
        depth: Int
    ) {
        let pageMetadata = PageMetadata(
            url: url,
            framework: framework,
            filePath: filePath,
            contentHash: contentHash,
            depth: depth,
            lastCrawled: Date()
        )
        metadata.pages[url] = pageMetadata
    }

    /// Finalize crawl and save metadata
    public func finalizeCrawl(stats: CrawlStatistics) throws {
        metadata.lastCrawl = Date()
        metadata.stats = stats

        // Ensure directory exists
        let directory = configuration.metadataFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try metadata.save(to: configuration.metadataFile)
    }

    // MARK: - Statistics

    /// Get current crawl statistics
    public func getStatistics() -> CrawlStatistics {
        metadata.stats
    }

    /// Update statistics
    public func updateStatistics(_ update: @Sendable (inout CrawlStatistics) -> Void) {
        update(&metadata.stats)
    }

    /// Get page count
    public func getPageCount() -> Int {
        metadata.pages.count
    }

    /// Get last crawl date
    public func getLastCrawl() -> Date? {
        metadata.lastCrawl
    }
}
