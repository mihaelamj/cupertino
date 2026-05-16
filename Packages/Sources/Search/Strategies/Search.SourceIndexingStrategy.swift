import Foundation
import SearchModels

// MARK: - SourceIndexingStrategy

extension Search {
    /// Statistics returned by a completed ``SourceIndexingStrategy`` run.
    ///
    /// Aggregate these across all strategies to produce a full build report.
    ///
    /// The `breakdown` field carries the #588 import-diligence
    /// classification (door tier A / B / C + pre-INSERT garbage filter
    /// rejections by category). The breakdown counters are subsets of
    /// `skipped`; they classify the reason, they don't add new
    /// rejections. Strategies that don't classify (HIG, SwiftEvolution,
    /// SwiftOrg, AppleArchive, SampleCode) leave it at
    /// ``Search/ImportDiligenceBreakdown/zero``.
    public struct IndexStats: Sendable {
        /// The source identifier for this run (e.g., `"apple-docs"`).
        public let source: String
        /// Number of items successfully written to the search index.
        public let indexed: Int
        /// Number of items skipped due to missing files, parse errors, or filter rejections.
        /// Catch-all total — every entry in `breakdown` is a subset of
        /// this number.
        public let skipped: Int
        /// #588 import-diligence breakdown — door classifications and
        /// pre-INSERT garbage filter rejections by category. Zero for
        /// strategies that don't classify.
        public let breakdown: Search.ImportDiligenceBreakdown
        /// #671 — true when the strategy short-circuited because its
        /// input directory was absent or its catalog was empty. Lets
        /// the renderer print a clean `[source] skipped (<reason>)`
        /// line instead of `[source] indexed: 0, skipped: 0`, which
        /// falsely implies a failed indexing attempt against existing
        /// input. 99.9 % of users only have the bundled DB, no local
        /// corpus directory, and the clean-skip line is the right UX
        /// for that case.
        public let wasSkipped: Bool
        /// Human-readable reason for `wasSkipped` (e.g. `"no local
        /// corpus"`, `"no documents found"`, `"catalog empty"`). Nil
        /// when `wasSkipped == false`.
        public let skipReason: String?

        /// Create a new statistics value.
        ///
        /// The `breakdown` parameter defaults to `.zero` so existing
        /// strategies that don't classify keep their original
        /// initializer shape working unchanged. The `wasSkipped` /
        /// `skipReason` parameters default to `false` / `nil` so
        /// strategies that actually ran indexing keep their existing
        /// initializer shape too.
        public init(
            source: String,
            indexed: Int,
            skipped: Int,
            breakdown: Search.ImportDiligenceBreakdown = .zero,
            wasSkipped: Bool = false,
            skipReason: String? = nil
        ) {
            self.source = source
            self.indexed = indexed
            self.skipped = skipped
            self.breakdown = breakdown
            self.wasSkipped = wasSkipped
            self.skipReason = skipReason
        }
    }

    /// A single documentation source that knows how to index itself into a ``Search/Index``.
    ///
    /// Concrete conforming types encapsulate all per-source logic — directory paths,
    /// file formats, metadata parsing, and source-specific URI schemes — leaving
    /// ``Search/IndexBuilder`` as a pure orchestrator that iterates an array of strategies.
    ///
    /// Adding a new documentation source requires only a new conforming type.
    /// ``Search/IndexBuilder`` is unchanged.
    ///
    /// ## Implementing a strategy
    ///
    /// ```swift
    /// struct MySourceStrategy: Search.SourceIndexingStrategy {
    ///     let source = "my-source"
    ///     let directory: URL
    ///
    ///     func indexItems(
    ///         into index: Search.Index,
    ///         progress: (any Search.IndexingProgressReporting)?
    ///     ) async throws -> Search.IndexStats {
    ///         var indexed = 0, skipped = 0
    ///         // … scan, parse, call index.indexDocument(…)
    ///         return Search.IndexStats(source: source, indexed: indexed, skipped: skipped)
    ///     }
    /// }
    /// ```
    public protocol SourceIndexingStrategy: Sendable {
        /// The source identifier written into the FTS index (e.g., `"apple-docs"`).
        ///
        /// Must match the `source` column expected by search-result filtering so that
        /// queries scoped to a specific source work correctly.
        var source: String { get }

        /// Index all items for this source into the given search index.
        ///
        /// Implementations should:
        /// - Log start, periodic progress, and completion via the injected logger.
        /// - Call `progress?.report(processed:total:)` at regular intervals.
        /// - Catch per-item errors internally, count them as `skipped`, and continue.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional reporter, called periodically.
        /// - Returns: ``Search/IndexStats`` summarising the completed run.
        /// - Throws: Propagates only unrecoverable errors (e.g., database connection failure).
        func indexItems(
            into index: Search.Index,
            progress: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats
    }
}
