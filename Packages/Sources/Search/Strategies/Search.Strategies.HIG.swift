import Foundation
import Logging
import SharedConstants
import SharedModels
import SearchModels

// MARK: - HIGStrategy

extension Search {
    /// Indexes Apple Human Interface Guidelines documentation into the search index.
    ///
    /// HIG files are Markdown documents organised by category (e.g., `foundations`,
    /// `components`, `inputs`).  They apply to all Apple platforms and are indexed
    /// with fixed minimum availability versions that reflect universal HIG coverage.
    ///
    /// URI scheme: `hig://{category}/{filename}`
    ///
    /// ## Example
    /// ```swift
    /// let strategy = Search.HIGStrategy(higDirectory: higDir)
    /// let stats = try await strategy.indexItems(into: index, progress: nil)
    /// ```
    public struct HIGStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index.
        public let source = Shared.Constants.SourcePrefix.hig

        /// Root directory containing the HIG Markdown files.
        public let higDirectory: URL

        /// Create a strategy for indexing Human Interface Guidelines documentation.
        ///
        /// - Parameter higDirectory: The root directory of the HIG corpus.
        public init(higDirectory: URL) {
            self.higDirectory = higDirectory
        }

        /// Index all HIG Markdown files found under ``higDirectory``.
        ///
        /// All HIG pages are indexed with universal platform availability
        /// (iOS 2.0 / macOS 10.0 / tvOS 9.0 / watchOS 2.0 / visionOS 1.0).
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional progress callback, called every 100 items.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        public func indexItems(
            into index: Search.Index,
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats {
            guard FileManager.default.fileExists(atPath: higDirectory.path) else {
                Logging.Log.info(
                    "⚠️  HIG directory not found: \(higDirectory.path)",
                    category: .search
                )
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            let markdownFiles = try Search.StrategyHelpers.findMarkdownFiles(in: higDirectory)
            guard !markdownFiles.isEmpty else {
                Logging.Log.info("⚠️  No HIG documentation found", category: .search)
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            Logging.Log.info(
                "🎨 Indexing \(markdownFiles.count) Human Interface Guidelines pages...",
                category: .search
            )

            var indexed = 0
            var skipped = 0

            for (idx, file) in markdownFiles.enumerated() {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    skipped += 1
                    continue
                }

                let category = Search.StrategyHelpers.extractFrameworkFromPath(
                    file, relativeTo: higDirectory
                ) ?? "general"

                let metadata = Search.StrategyHelpers.extractHIGMetadata(from: content)
                let title = metadata["title"]
                    ?? Search.StrategyHelpers.extractTitle(from: content)
                    ?? file.deletingPathExtension().lastPathComponent

                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "hig://\(category)/\(filename)"

                let contentHash = Shared.Models.HashUtilities.sha256(of: content)
                let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()

                do {
                    // HIG applies universally to all Apple platforms.
                    try await index.indexDocument(Search.Index.IndexDocumentParams(
                        uri: uri,
                        source: source,
                        framework: category,
                        title: title,
                        content: content,
                        filePath: file.path,
                        contentHash: contentHash,
                        lastCrawled: modDate,
                        minIOS: "2.0",
                        minMacOS: "10.0",
                        minTvOS: "9.0",
                        minWatchOS: "2.0",
                        minVisionOS: "1.0",
                        availabilitySource: "universal",
                    ))
                    indexed += 1
                } catch {
                    Logging.Log.error(
                        "❌ Failed to index \(uri): \(error)", category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    progress?(idx + 1, markdownFiles.count)
                    Logging.Log.info(
                        "   Progress: \(idx + 1)/\(markdownFiles.count)", category: .search
                    )
                }
            }

            Logging.Log.info(
                "   HIG: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }
    }
}
