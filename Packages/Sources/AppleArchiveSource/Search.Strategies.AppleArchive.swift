import Foundation
import LoggingModels
import SearchModels
import SearchStrategyHelpers
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
        public let source = Shared.Constants.SourcePrefix.appleArchive

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
        ///   - index: An object conforming to both ``SearchModels/Search/Database`` and ``SearchModels/Search/IndexWriter`` (the production conformer is the
        /// ``SearchSQLite/Search/Index``
        /// actor).
        ///   - progress: Optional progress callback, called every 100 items.
        /// - Returns: ``SearchModels/Search/IndexStats`` with indexed and skipped counts.
        // swiftlint:disable:next function_body_length
        // (pre-#1080 baseline was 110 lines; #1080 extracted the
        // availability-resolution to a helper, dropping the body to
        // 114. The remaining length is the unavoidable per-page
        // indexing loop covering metadata extraction + poison
        // defence + structured-page assembly + indexer call — each
        // of those stages is short on its own and splitting them
        // across helpers would obscure the linear page-processing
        // narrative.)
        public func indexItems(
            into index: any Search.Database & Search.IndexWriter,
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

                let metadata = Search.StrategyHelpers.extractArchiveMetadata(from: content)
                // Guide identifier is a property of the document: the crawler
                // stamps it into the frontmatter (`guide:`). Read it from
                // there; fall back to the on-disk layout only for legacy
                // corpora that predate the key (Principle 7: no stored value
                // derived from filesystem layout).
                let guideID = metadata["guide"]
                    ?? Search.StrategyHelpers.extractFrameworkFromPath(file, relativeTo: archiveDirectory)
                    ?? "unknown"
                let title = metadata["title"]
                    ?? Search.StrategyHelpers.extractTitle(from: content)
                    ?? file.deletingPathExtension().lastPathComponent
                let bookTitle = metadata["book"] ?? guideID
                // #1090: use the canonical framework name from the
                // .md frontmatter directly. Pre-fix we called
                // `expandFrameworkSynonyms` which joined the
                // canonical name with its synonyms via ", " (e.g.
                // "CoreGraphics" → "CoreGraphics, Quartz2D"), and
                // the joined string landed in `docs_metadata.framework`.
                // The synonym-search responsibility now lives on the
                // `framework_aliases.synonyms` field (post-#1042), so
                // the framework field no longer needs to carry
                // alternative names inline. Quartz2D is the C-level
                // drawing API inside CoreGraphics — not a separate
                // framework. Dropping the join surfaces the canonical
                // name in search output.
                let framework = metadata["framework"] ?? bookTitle

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

                let availability = await Self.resolveAvailability(
                    framework: framework,
                    cache: &frameworkAvailabilityCache,
                    index: index
                )

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
                        // #1080: tag the source so callers can
                        // distinguish per-page availability (from the
                        // page's own metadata) from inferred (from
                        // our static framework table). For apple-
                        // archive this is always inferred today.
                        overrideAvailabilitySource: (
                            availability.minIOS != nil ||
                                availability.minMacOS != nil ||
                                availability.minTvOS != nil ||
                                availability.minWatchOS != nil ||
                                availability.minVisionOS != nil
                        ) ? "framework-inferred" : nil
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

        /// #1080: per-framework availability resolution. Order: cache
        /// → static table → per-DB lookup (self-referential for
        /// apple-archive, kept as a future-proof fallback). Extracted
        /// from `indexItems` to keep that loop under the
        /// `function_body_length` lint threshold.
        private static func resolveAvailability(
            framework: String,
            cache: inout [String: Search.FrameworkAvailability],
            index: any Search.Database & Search.IndexWriter
        ) async -> Search.FrameworkAvailability {
            if let cached = cache[framework] {
                return cached
            }
            if let staticAvailability = AppleArchiveFrameworkAvailability.availability(for: framework) {
                cache[framework] = staticAvailability
                return staticAvailability
            }
            let dbLookup = await index.getFrameworkAvailability(framework: framework)
            cache[framework] = dbLookup
            return dbLookup
        }
    }
}
