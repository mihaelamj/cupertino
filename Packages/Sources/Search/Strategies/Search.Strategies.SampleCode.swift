import Foundation
import LoggingModels
import SearchModels
import SharedConstants
// MARK: - SampleCodeStrategy

extension Search {
    /// Indexes the Apple sample code catalog into the search index.
    ///
    /// The catalog is provided via the injected `sampleCatalogProvider`
    /// conformer, which the composition root (the CLI binary) backs with
    /// `Sample.Core.Catalog`. Test harnesses pass a struct that returns
    /// a `Search.SampleCatalogState` fixture directly.
    ///
    /// Each entry's framework availability is looked up from the search
    /// index and cached to avoid redundant database round-trips.
    ///
    /// If the catalog is missing this strategy logs a helpful message and
    /// returns cleanly rather than raising an error.
    ///
    /// ## Example
    /// ```swift
    /// let strategy = Search.SampleCodeStrategy(sampleCatalogProvider: MyProvider())
    /// let stats = try await strategy.indexItems(into: index, progress: nil)
    /// ```
    public struct SampleCodeStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index.
        public let source = "sample-code"

        /// Conformer that returns the current state of the Apple
        /// sample-code catalog. Injected so this target doesn't depend
        /// on `CoreSampleCode`; the composition root supplies the
        /// adapter over `Sample.Core.Catalog`.
        private let sampleCatalogProvider: any Search.SampleCatalogProvider

        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        /// Create a strategy for indexing the sample code catalog.
        ///
        /// - Parameter sampleCatalogProvider: Conformer that returns
        ///   the `Search.SampleCatalogState` to index. Injected at the
        ///   composition root so the strategy can read the catalog
        ///   without depending on the `CoreSampleCode` target directly.
        public init(
            sampleCatalogProvider: any Search.SampleCatalogProvider,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.sampleCatalogProvider = sampleCatalogProvider
            self.logger = logger
        }

        /// Index all sample code entries from the catalog fetch closure.
        ///
        /// When the catalog is absent, logs a user-friendly message and
        /// returns with zero counts.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional progress callback, called every 100 items.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        public func indexItems(
            into index: Search.Index,
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats {
            let state = await sampleCatalogProvider.fetch()

            let entries: [Search.SampleCatalogEntry]
            switch state {
            case .loaded(let loadedEntries):
                logger.info(
                    "📦 Indexing sample code catalog from on-disk catalog.json (#214)...",
                    category: .search
                )
                entries = loadedEntries
            case .missing(let onDiskPath):
                logger.info(
                    "⚠️  No sample-code catalog at \(onDiskPath) — skipping sample-code indexing.",
                    category: .search
                )
                logger.info(
                    "    Run `cupertino fetch --type code` to populate the catalog, then re-run save.",
                    category: .search
                )
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            guard !entries.isEmpty else {
                logger.info(
                    "⚠️  Sample-code catalog parsed but contained zero entries; skipping.",
                    category: .search
                )
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            logger.info(
                "📚 Indexing \(entries.count) sample code entries...", category: .search
            )

            var indexed = 0
            var skipped = 0
            var frameworkAvailabilityCache: [String: Search.FrameworkAvailability] = [:]

            for (idx, entry) in entries.enumerated() {
                do {
                    let availability: Search.FrameworkAvailability
                    if let cached = frameworkAvailabilityCache[entry.framework] {
                        availability = cached
                    } else {
                        availability = await index.getFrameworkAvailability(
                            framework: entry.framework
                        )
                        frameworkAvailabilityCache[entry.framework] = availability
                    }

                    try await index.indexSampleCode(
                        url: entry.url,
                        framework: entry.framework,
                        title: entry.title,
                        description: entry.description,
                        zipFilename: entry.zipFilename,
                        webURL: entry.webURL,
                        minIOS: availability.minIOS,
                        minMacOS: availability.minMacOS,
                        minTvOS: availability.minTvOS,
                        minWatchOS: availability.minWatchOS,
                        minVisionOS: availability.minVisionOS
                    )
                    indexed += 1
                } catch {
                    logger.error(
                        "❌ Failed to index sample code \(entry.title): \(error)",
                        category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % 100 == 0 {
                    progress?(idx + 1, entries.count)
                    logger.info(
                        "   Progress: \(idx + 1)/\(entries.count)", category: .search
                    )
                }
            }

            logger.info(
                "   Sample Code: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }
    }
}
