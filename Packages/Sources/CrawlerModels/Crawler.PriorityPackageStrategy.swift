import Foundation

// MARK: - Crawler.PriorityPackageStrategy

/// Strategy for generating a priority-package catalog from a
/// Swift.org documentation tree. GoF Strategy pattern: hides the
/// concrete `Core.PackageIndexing.PriorityPackageGenerator` actor
/// behind a named contract.
///
/// The Crawler target calls this when a Swift.org crawl finishes,
/// to write `priority-packages.json` for the next package-indexing
/// run. The composition root supplies a
/// `LivePriorityPackageStrategy` that wraps the actor; tests can
/// supply a stub that returns a fixture outcome.
public extension Crawler {
    protocol PriorityPackageStrategy: Sendable {
        /// Walk the Swift.org documentation tree at
        /// `swiftOrgDocsPath`, collect every referenced Swift
        /// package, and write the catalog to `outputPath`. Returns
        /// the aggregate outcome so the crawler can log it.
        func generate(
            swiftOrgDocsPath: URL,
            outputPath: URL
        ) async throws -> PriorityPackageOutcome
    }

    /// Aggregate statistics emitted by a
    /// `PriorityPackageStrategy.generate(...)` run.
    struct PriorityPackageOutcome: Sendable {
        public let totalUniqueReposFound: Int

        public init(totalUniqueReposFound: Int) {
            self.totalUniqueReposFound = totalUniqueReposFound
        }
    }
}
