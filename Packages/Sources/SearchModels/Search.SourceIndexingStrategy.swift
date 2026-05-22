import Foundation

// MARK: - Search.SourceIndexingStrategy

extension Search {
    /// A single documentation source that knows how to index itself.
    ///
    /// Concrete conforming types encapsulate all per-source logic:
    /// directory paths, file formats, metadata parsing, source-specific
    /// URI schemes. `Search.IndexBuilder` orchestrates by iterating an
    /// array of strategies; adding a new documentation source requires
    /// only a new conforming type, with `Search.IndexBuilder` unchanged.
    ///
    /// Lifted from `Search/Strategies/Search.SourceIndexingStrategy.swift`
    /// (Search target) to `SearchModels` by epic #893's child #897 so
    /// the protocol is reachable from foundation-only consumers. The
    /// rewire of `Search.IndexBuilder` + the 6 concrete strategies to
    /// consume `any Search.Database & Search.IndexWriter` via the
    /// `indexItems(into:progress:)` parameter also lands under #897.
    /// (The 6 concrete conformers as of #897: `AppleArchiveStrategy`,
    /// `AppleDocsStrategy`, `HIGStrategy`, `SampleCodeStrategy`,
    /// `SwiftEvolutionStrategy`, `SwiftOrgStrategy`. `StrategyHelpers`
    /// stays a utility namespace; the previous `SwiftPackagesStrategy`
    /// was removed in #789.)
    ///
    /// ## Implementing a strategy
    ///
    /// ```swift
    /// struct MySourceStrategy: Search.SourceIndexingStrategy {
    ///     let source = "my-source"
    ///     let directory: URL
    ///
    ///     func indexItems(
    ///         into index: any Search.Database & Search.IndexWriter,
    ///         progress: (any Search.IndexingProgressReporting)?
    ///     ) async throws -> Search.IndexStats {
    ///         var indexed = 0, skipped = 0
    ///         // scan, parse, call index.indexDocument(...) / index.indexStructuredDocument(...)
    ///         return Search.IndexStats(source: source, indexed: indexed, skipped: skipped)
    ///     }
    /// }
    /// ```
    public protocol SourceIndexingStrategy: Sendable {
        /// The source identifier written into the FTS index (e.g., `"apple-docs"`).
        ///
        /// Must match the `source` column expected by search-result
        /// filtering so that queries scoped to a specific source work
        /// correctly.
        var source: String { get }

        /// Index all items for this source into the given search index.
        ///
        /// Implementations should:
        /// - Log start, periodic progress, and completion via the injected logger.
        /// - Call `progress?.report(processed:total:)` at regular intervals.
        /// - Catch per-item errors internally, count them as `skipped`, and continue.
        ///
        /// - Parameters:
        ///   - index: An object that conforms to both `Search.Database`
        ///     (read; for `getFrameworkAvailability` lookups) and
        ///     `Search.IndexWriter` (write; for the index-mutation
        ///     methods).
        ///   - progress: Optional reporter, called periodically.
        /// - Returns: `Search.IndexStats` summarising the completed run.
        /// - Throws: Propagates only unrecoverable errors (e.g., database connection failure).
        func indexItems(
            into index: any Search.Database & Search.IndexWriter,
            progress: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats
    }
}
