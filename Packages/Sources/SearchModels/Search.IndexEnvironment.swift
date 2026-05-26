import Foundation
import LoggingModels

// MARK: - Search.IndexEnvironment

extension Search {
    /// Shared dependencies passed into `Search.SourceProvider.makeStrategy(env:)`
    /// at composition time. Bundles the deps that more than one
    /// strategy needs: paths for the source's content directory, a
    /// logger, and the markdown-to-structured-page strategy seam
    /// concretes need to consume.
    ///
    /// Per-source strategies that don't need a given dep simply
    /// ignore it; the bundle keeps the `SourceProvider.makeStrategy`
    /// signature stable across all conformers. Per gof-di-rules § 2
    /// the deps appear at the strategy's init site (via this struct's
    /// fields) rather than via process-wide statics.
    public struct IndexEnvironment: Sendable {
        /// Resolved path the source reads its on-disk content from.
        /// CLI composition root constructs this against the
        /// `FetchInfo.defaultOutputDirKey` value via `Shared.Paths.live()`.
        public let sourceDirectory: URL

        /// Logger threaded down by composition root per gof-di-rules § 2.
        public let logger: any LoggingModels.Logging.Recording

        /// Markdown-to-structured-page strategy seam. Per-source
        /// strategies that parse markdown (apple-docs, hig, swift-org)
        /// invoke this; others (samples, packages) ignore it.
        public let markdownStrategy: any Search.MarkdownToStructuredPageStrategy

        /// Optional import-log sink for per-doc audit lines (#588).
        /// Per-source strategies that want to emit a structured
        /// audit log read this; others ignore it.
        public let importLogSink: (any Search.ImportLogSink)?

        /// Optional catalog provider for the sample-code source.
        /// Established as the seam pattern by #1012 (Phase 1C of
        /// epic #1007): when a per-source strategy needs a
        /// domain-specific dep not shared with other sources, add
        /// it here as an optional field. Sources that don't need it
        /// (apple-docs, hig) ignore it; SampleCodeSource preconditions
        /// non-nil at `makeStrategy(env:)` time per fail-loud-at-the-door
        /// (docs/PRINCIPLES.md). Future per-source migrations follow
        /// the same pattern.
        public let sampleCatalogProvider: (any Search.SampleCatalogProvider)?

        public init(
            sourceDirectory: URL,
            logger: any LoggingModels.Logging.Recording,
            markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
            importLogSink: (any Search.ImportLogSink)? = nil,
            sampleCatalogProvider: (any Search.SampleCatalogProvider)? = nil
        ) {
            self.sourceDirectory = sourceDirectory
            self.logger = logger
            self.markdownStrategy = markdownStrategy
            self.importLogSink = importLogSink
            self.sampleCatalogProvider = sampleCatalogProvider
        }
    }
}
