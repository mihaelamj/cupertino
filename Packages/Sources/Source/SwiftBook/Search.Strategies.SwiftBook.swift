import Foundation
import LoggingModels
import SearchModels
import SearchStrategyHelpers
import SharedConstants

// MARK: - SwiftBookStrategy

extension Search {
    /// Indexes Swift Book pages (URL-prefix-tagged `swift-book`) into
    /// `swift-book.db`. Companion to `Search.SwiftOrgStrategy`: the two
    /// strategies walk the same on-disk corpus directory but each
    /// filters per-page emission to its own sub-source via a `Scope`
    /// flag passed to the shared
    /// `Search.StrategyHelpers.crawlSwiftDocumentation` helper.
    ///
    /// **Pluggability shape** (per #1038 + `feedback_sources_100pct_pluggable`):
    /// the file-walking + page-decoding + emission logic lives in
    /// `SearchStrategyHelpers` (a neutral target both `SwiftOrgSource`
    /// and `SwiftBookSource` depend on). Each per-source strategy
    /// concrete is a thin delegator owning only its own constructor
    /// args + scope flag. SwiftBookSource does NOT import SwiftOrgSource
    /// (cross-source-target imports are forbidden by
    /// `mihaela-agents/Rules/swift/per-package-import-contract.md`).
    ///
    /// Pre-#1038 SwiftBookSource was a view-source: its
    /// `makeStrategy(env:)` returned a no-op and SwiftOrgStrategy emitted
    /// both sub-sources into `swift-documentation.db`. Post-#1038
    /// SwiftBookSource owns its own active strategy and its own
    /// destination DB (`swift-book.db`).
    public struct SwiftBookStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index for this
        /// strategy's summary line; per-page rows carry their own
        /// URL-prefix-derived tag (`swift-book` for any page emitted
        /// by this strategy, since the scope filter discards everything
        /// else).
        public let source = Shared.Constants.SourcePrefix.swiftBook

        /// Root directory containing the Swift documentation corpus
        /// (shared with SwiftOrgStrategy; the two strategies walk the
        /// same crawl tree but emit different subsets).
        public let swiftOrgDirectory: URL

        /// Strategy for converting raw markdown to a structured page.
        /// Injected so this target doesn't depend on `CoreJSONParser`.
        private let markdownStrategy: any Search.MarkdownToStructuredPageStrategy

        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        public init(
            swiftOrgDirectory: URL,
            markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.swiftOrgDirectory = swiftOrgDirectory
            self.markdownStrategy = markdownStrategy
            self.logger = logger
        }

        public func indexItems(
            into index: any Search.Database & Search.IndexWriter,
            progress: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats {
            try await Search.StrategyHelpers.crawlSwiftDocumentation(
                swiftOrgDirectory: swiftOrgDirectory,
                markdownStrategy: markdownStrategy,
                logger: logger,
                scope: .swiftBookOnly,
                summarySource: source,
                into: index,
                progress: progress
            )
        }
    }
}
