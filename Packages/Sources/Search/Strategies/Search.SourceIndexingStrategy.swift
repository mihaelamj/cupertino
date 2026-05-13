import Foundation
import SearchModels

// MARK: - SourceIndexingStrategy

extension Search {
    /// A callback fired periodically during an indexing run.
    ///
    /// The two arguments are `(processed, total)` — the number of items handled so far
    /// and the total number of items in the source, respectively.  Callers use these
    /// values to drive progress bars or log progress messages.
    public typealias IndexingProgressCallback = @Sendable (Int, Int) -> Void

    /// Statistics returned by a completed ``SourceIndexingStrategy`` run.
    ///
    /// Aggregate these across all strategies to produce a full build report.
    public struct IndexStats: Sendable {
        /// The source identifier for this run (e.g., `"apple-docs"`).
        public let source: String
        /// Number of items successfully written to the search index.
        public let indexed: Int
        /// Number of items skipped due to missing files, parse errors, or filter rejections.
        public let skipped: Int

        /// Create a new statistics value.
        ///
        /// - Parameters:
        ///   - source: The source identifier (must match the strategy's ``SourceIndexingStrategy/source``).
        ///   - indexed: Items successfully written to the index.
        ///   - skipped: Items that were not indexed.
        public init(source: String, indexed: Int, skipped: Int) {
            self.source = source
            self.indexed = indexed
            self.skipped = skipped
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
    ///         progress: Search.IndexingProgressCallback?
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
        /// - Log start, periodic progress, and completion via `Logging.Log`.
        /// - Call `progress` at regular intervals with `(processed, total)`.
        /// - Catch per-item errors internally, count them as `skipped`, and continue.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional callback, called periodically with `(processed, total)`.
        /// - Returns: ``Search/IndexStats`` summarising the completed run.
        /// - Throws: Propagates only unrecoverable errors (e.g., database connection failure).
        func indexItems(
            into index: Search.Index,
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats
    }
}
