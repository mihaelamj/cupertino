import Foundation
import Logging
import SharedConfiguration
import SharedConstants
import SharedCore
import SharedModels

// MARK: - Crawler State Manager

/// Manages crawler state including metadata and change detection
public actor CrawlerState {
    private let configuration: Shared.ChangeDetectionConfiguration
    private var metadata: Shared.Models.CrawlMetadata
    private var autoSaveInterval: TimeInterval = Shared.Constants.Interval.autoSave
    private var lastAutoSave: Date = .init()

    public init(configuration: Shared.ChangeDetectionConfiguration) {
        self.configuration = configuration
        metadata = Shared.Models.CrawlMetadata()

        // Load existing metadata if available
        if FileManager.default.fileExists(atPath: configuration.metadataFile.path) {
            do {
                var loadedMetadata = try Shared.Models.CrawlMetadata.load(from: configuration.metadataFile)

                // Validate metadata by checking if files actually exist
                if Self.validateMetadata(loadedMetadata, metadataFile: configuration.metadataFile) {
                    // Cross-machine portability: PageMetadata.filePath is an
                    // absolute string captured on the writing host. After rsync
                    // to a machine with a different home dir, those strings
                    // point at nothing — SearchIndexBuilder + DocsResourceProvider
                    // would silently fail to read each page, and our own
                    // validateMetadata would have already wiped crawlState.
                    // Rebase on load so all downstream consumers see paths
                    // under the *current* outputDir.
                    let outputDir = configuration.metadataFile.deletingLastPathComponent()
                    Self.rebasePagePaths(in: &loadedMetadata, to: outputDir)

                    metadata = loadedMetadata
                    Logging.Logger.crawler.info("✅ Loaded existing metadata: \(metadata.pages.count) pages")
                } else {
                    Logging.Logger.crawler.warning("⚠️  Not trusting lying metadata - file counts don't match, starting fresh")
                }
            } catch {
                Logging.Logger.crawler.warning("⚠️  Failed to load metadata: \(error.localizedDescription), starting with fresh metadata")
            }
        }
    }

    /// Validate that metadata matches reality by spot-checking file existence.
    /// File existence is checked at the *expected* path under the metadata
    /// file's parent directory (`outputDir / framework / filename`), not at
    /// the absolute path stored in `page.filePath` — that string was captured
    /// on the writing host and may point under the wrong home directory after
    /// the metadata has been rsynced between machines.
    static func validateMetadata(_ metadata: Shared.Models.CrawlMetadata, metadataFile: URL) -> Bool {
        // If metadata claims many pages, verify some actually exist
        guard !metadata.pages.isEmpty else { return true }

        // Check if the output directory exists
        let outputDir = metadataFile.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: outputDir.path) else {
            return false
        }

        // Spot check: verify at least 10% of claimed files exist (up to 100 checks)
        let samplesToCheck = min(100, max(1, metadata.pages.count / 10))
        let pagesList = Array(metadata.pages.values)
        var existingCount = 0

        for sampleIdx in 0..<samplesToCheck {
            let index = sampleIdx * pagesList.count / samplesToCheck
            let page = pagesList[index]
            // Try the portable canonical path first (rsync-friendly); fall
            // back to the saved absolute path so existing layouts and tests
            // that don't follow framework/file canonicalisation still validate.
            let portable = Self.expectedFilePath(for: page, under: outputDir)
            if FileManager.default.fileExists(atPath: portable)
                || FileManager.default.fileExists(atPath: page.filePath) {
                existingCount += 1
            }
        }

        // If less than 50% of sampled files exist, metadata is lying
        let existenceRatio = Double(existingCount) / Double(samplesToCheck)
        if existenceRatio < 0.5 {
            Logging.Logger.crawler.warning("⚠️  Only \(Int(existenceRatio * 100))% of metadata files exist")
            return false
        }

        return true
    }

    /// Compute the expected on-disk path for `page` relative to `outputDir`.
    /// Uses `framework` + the basename of the saved `filePath`, so the result
    /// only depends on data captured *within* the metadata, never on the
    /// absolute prefix the writing host happened to use.
    static func expectedFilePath(for page: Shared.Models.PageMetadata, under outputDir: URL) -> String {
        let filename = (page.filePath as NSString).lastPathComponent
        return outputDir
            .appendingPathComponent(page.framework)
            .appendingPathComponent(filename)
            .path
    }

    /// Rewrite each page's `filePath` to live under `outputDir` *if and only
    /// if* the saved path no longer points at an existing file. This catches
    /// the rsync-from-another-host case (saved absolute path is foreign,
    /// portable canonical path resolves locally) without disturbing layouts
    /// where the saved path is still valid (e.g. tests with non-canonical
    /// fixture paths, or runs against custom output directories).
    /// Idempotent.
    static func rebasePagePaths(in metadata: inout Shared.Models.CrawlMetadata, to outputDir: URL) {
        for (url, page) in metadata.pages {
            // Saved path still resolves → leave it alone.
            if FileManager.default.fileExists(atPath: page.filePath) {
                continue
            }
            let expected = Self.expectedFilePath(for: page, under: outputDir)
            if expected != page.filePath {
                metadata.pages[url] = Shared.Models.PageMetadata(
                    url: page.url,
                    framework: page.framework,
                    filePath: expected,
                    contentHash: page.contentHash,
                    depth: page.depth,
                    lastCrawled: page.lastCrawled
                )
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
        let pageMetadata = Shared.Models.PageMetadata(
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
            metadata.frameworks[fwKey] = Shared.Models.FrameworkStats(
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
            metadata.frameworks[fwKey] = Shared.Models.FrameworkStats(
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
    public func getFrameworkStats(framework: String) -> Shared.Models.FrameworkStats? {
        metadata.frameworks[framework.lowercased()]
    }

    /// Get all framework stats
    public func getAllFrameworkStats() -> [String: Shared.Models.FrameworkStats] {
        metadata.frameworks
    }

    /// Finalize crawl and save metadata
    public func finalizeCrawl(stats: Shared.Models.CrawlStatistics) throws {
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
    public func getStatistics() -> Shared.Models.CrawlStatistics {
        metadata.stats
    }

    /// Update statistics
    public func updateStatistics(_ update: @Sendable (inout Shared.Models.CrawlStatistics) -> Void) {
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
        let queuedURLs = queue.map { Shared.Models.QueuedURL(url: $0.url.absoluteString, depth: $0.depth) }

        metadata.crawlState = Shared.Models.CrawlSessionState(
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
    public func getSavedSession() -> Shared.Models.CrawlSessionState? {
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
