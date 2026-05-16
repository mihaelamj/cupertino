import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - AppleArchiveStrategy

extension Search {
    /// Indexes Apple Archive legacy documentation into the search index.
    ///
    /// The Apple Archive source contains older developer documentation in Markdown format,
    /// organised by guide UID (book identifier).  Each file's YAML front matter supplies
    /// the title, book title, and optional framework name used for availability look-up.
    ///
    /// URI scheme: `apple-archive://{guideUID}/{filename}`
    ///
    /// ## Example
    /// ```swift
    /// let strategy = Search.AppleArchiveStrategy(archiveDirectory: archiveDir)
    /// let stats = try await strategy.indexItems(into: index, progress: nil)
    /// ```
    public struct AppleArchiveStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index.
        public let source = "apple-archive"

        /// Root directory containing the Apple Archive Markdown files.
        public let archiveDirectory: URL

        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        /// Create a strategy for indexing Apple Archive documentation.
        ///
        /// - Parameter archiveDirectory: The root directory of the archive corpus.
        public init(
            archiveDirectory: URL,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.archiveDirectory = archiveDirectory
            self.logger = logger
        }

        /// Index all Apple Archive Markdown files found under ``archiveDirectory``.
        ///
        /// Each file's framework availability is looked up from the search index and
        /// cached per framework to avoid redundant database round-trips.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional progress callback, called every 100 items.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        public func indexItems(
            into index: Search.Index,
            progress: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats {
            guard FileManager.default.fileExists(atPath: archiveDirectory.path) else {
                // #671 — clean-skip when no local corpus is available.
                return IndexStats(
                    source: source,
                    indexed: 0,
                    skipped: 0,
                    wasSkipped: true,
                    skipReason: "no local corpus"
                )
            }

            let markdownFiles = try Search.StrategyHelpers.findMarkdownFiles(in: archiveDirectory)
            guard !markdownFiles.isEmpty else {
                // #671 — clean-skip when the dir exists but has no archive pages.
                return IndexStats(
                    source: source,
                    indexed: 0,
                    skipped: 0,
                    wasSkipped: true,
                    skipReason: "no documents found"
                )
            }

            logger.info(
                "📜 Indexing \(markdownFiles.count) Apple Archive documentation pages...",
                category: .search
            )

            var indexed = 0
            var skipped = 0
            var frameworkAvailabilityCache: [String: Search.FrameworkAvailability] = [:]

            for (idx, file) in markdownFiles.enumerated() {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    skipped += 1
                    continue
                }

                let guideID = Search.StrategyHelpers.extractFrameworkFromPath(
                    file, relativeTo: archiveDirectory
                ) ?? "unknown"

                let metadata = Search.StrategyHelpers.extractArchiveMetadata(from: content)
                let title = metadata["title"]
                    ?? Search.StrategyHelpers.extractTitle(from: content)
                    ?? file.deletingPathExtension().lastPathComponent
                let bookTitle = metadata["book"] ?? guideID
                let baseFramework = metadata["framework"] ?? bookTitle
                let framework = Search.StrategyHelpers.expandFrameworkSynonyms(baseFramework)

                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "apple-archive://\(guideID)/\(filename)"

                // #429: indexer-side poison defence, same checks as
                // apple-docs.
                if Search.StrategyHelpers.titleLooksLikeHTTPErrorTemplate(title) {
                    logger.error(
                        "⛔ Skipping HTTP-error-template archive page (#429 defence): title=\(title.prefix(60)) file=\(file.lastPathComponent)",
                        category: .search
                    )
                    skipped += 1
                    continue
                }
                if Search.StrategyHelpers.contentLooksLikeJavaScriptFallback(content) {
                    logger.error(
                        "⛔ Skipping JS-fallback archive page (#429 defence): title=\(title.prefix(60)) file=\(file.lastPathComponent)",
                        category: .search
                    )
                    skipped += 1
                    continue
                }

                let contentHash = Shared.Models.HashUtilities.sha256(of: content)
                let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()

                let availability: Search.FrameworkAvailability
                if let cached = frameworkAvailabilityCache[framework] {
                    availability = cached
                } else {
                    availability = await index.getFrameworkAvailability(framework: framework)
                    frameworkAvailabilityCache[framework] = availability
                }

                do {
                    // #668 — write a structured row in addition to the FTS row so
                    // `docs_structured.(missing)` rate drops from 100 % to 0 % for
                    // apple-archive. `.article` kind lets #177 rerank + #616
                    // kind-aware tiebreak function on these legacy programming guides.
                    let pageURL = URL(string: uri) ?? URL(fileURLWithPath: file.path)
                    let structuredPage = Search.StrategyHelpers.makeArticleStructuredPage(
                        url: pageURL,
                        title: title,
                        rawMarkdown: content,
                        crawledAt: modDate,
                        contentHash: contentHash
                    )
                    let pageJSON = Search.StrategyHelpers.encodeStructuredPageToJSON(structuredPage)

                    try await index.indexStructuredDocument(
                        uri: uri,
                        source: source,
                        framework: framework,
                        page: structuredPage,
                        jsonData: pageJSON,
                        overrideMinIOS: availability.minIOS,
                        overrideMinMacOS: availability.minMacOS,
                        overrideMinTvOS: availability.minTvOS,
                        overrideMinWatchOS: availability.minWatchOS,
                        overrideMinVisionOS: availability.minVisionOS,
                        overrideAvailabilitySource: availability.minIOS != nil ? "framework" : nil
                    )
                    indexed += 1
                } catch {
                    logger.error(
                        "❌ Failed to index \(uri): \(error)", category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    progress?.report(processed: idx + 1, total: markdownFiles.count)
                    logger.info(
                        "   Progress: \(idx + 1)/\(markdownFiles.count)", category: .search
                    )
                }
            }

            logger.info(
                "   Apple Archive: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }
    }
}
