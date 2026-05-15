import CoreProtocols
import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - SwiftPackagesStrategy

extension Search {
    /// Indexes the bundled Swift Packages catalog into the search index.
    ///
    /// The catalog is loaded from the embedded ``Core/Protocols/SwiftPackagesCatalog``
    /// resource compiled into the binary.  This source requires no external directories
    /// or network access.
    ///
    /// ## Example
    /// ```swift
    /// let strategy = Search.SwiftPackagesStrategy()
    /// let stats = try await strategy.indexItems(into: index, progress: nil)
    /// ```
    public struct SwiftPackagesStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index.
        public let source = "swift-packages"

        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        /// Create a strategy for indexing the bundled Swift Packages catalog.
        public init(logger: any LoggingModels.Logging.Recording) {
            self.logger = logger
        }

        /// Index all packages from the bundled catalog.
        ///
        /// Calls ``Search/Index/indexPackage(owner:name:repositoryURL:description:stars:isAppleOfficial:lastUpdated:)``
        /// for each entry.  Progress is reported every 500 packages.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional progress callback, called every 500 items.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        public func indexItems(
            into index: Search.Index,
            progress: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats {
            logger.info(
                "📦 Indexing Swift packages catalog from bundled resources...",
                category: .search
            )

            let packages = await Core.Protocols.SwiftPackagesCatalog.allPackages
            guard !packages.isEmpty else {
                logger.info("⚠️  No packages found in catalog", category: .search)
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            logger.info(
                "📚 Indexing \(packages.count) Swift packages...", category: .search
            )

            var indexed = 0
            var skipped = 0

            for (idx, package) in packages.enumerated() {
                do {
                    try await index.indexPackage(
                        owner: package.owner,
                        name: package.repo,
                        repositoryURL: package.url,
                        description: package.description,
                        stars: package.stars,
                        isAppleOfficial: package.owner.lowercased() == "apple",
                        lastUpdated: package.updatedAt
                    )
                    indexed += 1
                } catch {
                    logger.error(
                        "❌ Failed to index package \(package.repo): \(error)",
                        category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % 500 == 0 {
                    progress?.report(processed: idx + 1, total: packages.count)
                    logger.info(
                        "   Progress: \(idx + 1)/\(packages.count)", category: .search
                    )
                }
            }

            logger.info(
                "   Packages: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }
    }
}
