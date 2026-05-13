import CoreProtocols
import Foundation
import Logging
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

        /// Create a strategy for indexing the bundled Swift Packages catalog.
        public init() {}

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
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats {
            Logging.Log.info(
                "📦 Indexing Swift packages catalog from bundled resources...",
                category: .search
            )

            let packages = await Core.Protocols.SwiftPackagesCatalog.allPackages
            guard !packages.isEmpty else {
                Logging.Log.info("⚠️  No packages found in catalog", category: .search)
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            Logging.Log.info(
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
                    Logging.Log.error(
                        "❌ Failed to index package \(package.repo): \(error)",
                        category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % 500 == 0 {
                    progress?(idx + 1, packages.count)
                    Logging.Log.info(
                        "   Progress: \(idx + 1)/\(packages.count)", category: .search
                    )
                }
            }

            Logging.Log.info(
                "   Packages: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }
    }
}
