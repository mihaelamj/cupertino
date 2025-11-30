import Foundation
import Logging
import Shared

// MARK: - Crawler State Manager

/// Manages crawler state including metadata and change detection
public actor CrawlerState {
    private let configuration: Shared.ChangeDetectionConfiguration
    private var metadata: CrawlMetadata
    private var autoSaveInterval: TimeInterval = Shared.Constants.Interval.autoSave
    private var lastAutoSave: Date = .init()

    public init(configuration: Shared.ChangeDetectionConfiguration) {
        self.configuration = configuration
        metadata = CrawlMetadata()

        // Load existing metadata if available
        if FileManager.default.fileExists(atPath: configuration.metadataFile.path) {
            do {
                metadata = try CrawlMetadata.load(from: configuration.metadataFile)
                Logging.Logger.crawler.info("✅ Loaded existing metadata: \(metadata.pages.count) pages")
            } catch {
                Logging.Logger.crawler.warning("⚠️  Failed to load metadata: \(error.localizedDescription)")
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
        depth: Int,
        isNew: Bool = true
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

        // Update framework stats
        let fwKey = framework.lowercased()
        if var fwStats = metadata.frameworks[fwKey] {
            fwStats.pageCount += 1
            if isNew {
                fwStats.newPages += 1
            } else {
                fwStats.updatedPages += 1
            }
            fwStats.lastCrawled = Date()
            fwStats.crawlStatus = .inProgress
            metadata.frameworks[fwKey] = fwStats
        } else {
            metadata.frameworks[fwKey] = FrameworkStats(
                name: framework,
                pageCount: 1,
                newPages: isNew ? 1 : 0,
                updatedPages: isNew ? 0 : 1,
                lastCrawled: Date(),
                crawlStatus: .inProgress
            )
        }
    }

    /// Record an error for a framework
    public func recordFrameworkError(framework: String) {
        let fwKey = framework.lowercased()
        if var fwStats = metadata.frameworks[fwKey] {
            fwStats.errors += 1
            metadata.frameworks[fwKey] = fwStats
        } else {
            metadata.frameworks[fwKey] = FrameworkStats(
                name: framework,
                errors: 1,
                crawlStatus: .inProgress
            )
        }
    }

    /// Mark a framework as complete
    public func markFrameworkComplete(framework: String) {
        let fwKey = framework.lowercased()
        if var fwStats = metadata.frameworks[fwKey] {
            fwStats.crawlStatus = .complete
            fwStats.lastCrawled = Date()
            metadata.frameworks[fwKey] = fwStats
        }
    }

    /// Get stats for a specific framework
    public func getFrameworkStats(framework: String) -> FrameworkStats? {
        metadata.frameworks[framework.lowercased()]
    }

    /// Get all framework stats
    public func getAllFrameworkStats() -> [String: FrameworkStats] {
        metadata.frameworks
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

    // MARK: - Session State Management

    /// Save current crawl session state
    public func saveSessionState(
        visited: Set<String>,
        queue: [(url: URL, depth: Int)],
        startURL: URL,
        outputDirectory: URL
    ) throws {
        let queuedURLs = queue.map { QueuedURL(url: $0.url.absoluteString, depth: $0.depth) }

        metadata.crawlState = CrawlSessionState(
            visited: visited,
            queue: queuedURLs,
            startURL: startURL.absoluteString,
            outputDirectory: outputDirectory.path,
            sessionStartTime: metadata.stats.startTime ?? Date(),
            lastSaveTime: Date(),
            isActive: true
        )

        try metadata.save(to: configuration.metadataFile)
        lastAutoSave = Date()

        Logging.Logger.crawler.info("💾 Saved session state: \(visited.count) visited, \(queue.count) queued")
    }

    /// Check if auto-save is needed and perform it
    public func autoSaveIfNeeded(
        visited: Set<String>,
        queue: [(url: URL, depth: Int)],
        startURL: URL,
        outputDirectory: URL
    ) async throws {
        let now = Date()
        if now.timeIntervalSince(lastAutoSave) >= autoSaveInterval {
            try saveSessionState(visited: visited, queue: queue, startURL: startURL, outputDirectory: outputDirectory)
        }
    }

    /// Get saved session state for resuming
    public func getSavedSession() -> CrawlSessionState? {
        metadata.crawlState
    }

    /// Clear session state (call when crawl completes normally)
    public func clearSessionState() {
        metadata.crawlState = nil
    }

    /// Check if there's an active session to resume
    public func hasActiveSession() -> Bool {
        guard let state = metadata.crawlState else {
            return false
        }
        return state.isActive
    }
}
