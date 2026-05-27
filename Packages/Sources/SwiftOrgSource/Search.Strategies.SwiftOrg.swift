import CoreProtocols
import Foundation
import LoggingModels
import SearchModels
import SearchStrategyHelpers
import SharedConstants

// MARK: - SwiftOrgStrategy

extension Search {
    /// Indexes Swift.org documentation into the search index.
    ///
    /// Scans ``swiftOrgDirectory`` for both `.json` and `.md` documentation files,
    /// preferring JSON when both formats exist for the same page (matching the Apple
    /// Docs behaviour).  The first path component beneath ``swiftOrgDirectory`` is
    /// used as the source identifier (typically `"swift-book"` or `"swift-org"`).
    ///
    /// Pages from the Swift Book (`source == "swift-book"`) are indexed with universal
    /// platform availability to reflect that the Swift language itself runs everywhere
    /// Swift is supported.
    ///
    /// URI scheme: `{source}://{filename}`
    ///
    /// ## Example
    /// ```swift
    /// let strategy = Search.SwiftOrgStrategy(swiftOrgDirectory: swiftOrgDir)
    /// let stats = try await strategy.indexItems(into: index, progress: nil)
    /// ```
    public struct SwiftOrgStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index.
        ///
        /// Reports `"swift-org"` as the top-level source; individual pages may be
        /// sub-sourced as `"swift-book"` or `"swift-org"` based on the directory
        /// layout.
        public let source = Shared.Constants.SourcePrefix.swiftOrg

        /// Root directory containing the Swift.org documentation files.
        public let swiftOrgDirectory: URL

        /// Strategy for converting raw markdown to a structured page.
        /// Injected so this target doesn't depend on `CoreJSONParser`;
        /// the composition root supplies a concrete conformer wrapping
        /// `Core.JSONParser.MarkdownToStructuredPage.convert`.
        private let markdownStrategy: any Search.MarkdownToStructuredPageStrategy

        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        /// Create a strategy for indexing Swift.org documentation.
        ///
        /// - Parameters:
        ///   - swiftOrgDirectory: Root directory of the Swift.org corpus.
        ///   - markdownStrategy: Conformer that converts raw markdown into a
        ///     `Shared.Models.StructuredDocumentationPage`. Injected at the
        ///     composition root so the strategy can parse `.md` pages without
        ///     depending on the `CoreJSONParser` target directly.
        public init(
            swiftOrgDirectory: URL,
            markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.swiftOrgDirectory = swiftOrgDirectory
            self.markdownStrategy = markdownStrategy
            self.logger = logger
        }

        /// Index all Swift.org documentation pages found under ``swiftOrgDirectory``.
        ///
        /// Handles both `.json` (structured) and `.md` (Markdown) formats using the same
        /// dual-format dispatch as the Apple Docs strategy.  Applies is404Page checks and
        /// logs progress at regular intervals.
        ///
        /// - Parameters:
        ///   - index: An object conforming to both ``SearchModels/Search/Database`` and ``SearchModels/Search/IndexWriter`` (the production conformer is the
        /// ``SearchSQLite/Search/Index``
        /// actor).
        ///   - progress: Optional progress callback, called at regular intervals.
        /// - Returns: ``SearchModels/Search/IndexStats`` with indexed and skipped counts.
        public func indexItems(
            into index: any Search.Database & Search.IndexWriter,
            progress: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats {
            // Post the "diff db for each source" follow-up to #1037 (tracked
            // at #1038), the file-walking + page-decoding + emission logic
            // moved to `Search.StrategyHelpers.crawlSwiftDocumentation(...)`
            // so the sibling `SwiftBookSource` target can call it with a
            // different scope filter WITHOUT importing `SwiftOrgSource`
            // (per `mihaela-agents/Rules/swift/per-package-import-contract.md`).
            //
            // This strategy passes `.swiftOrgOnly` so only pages whose
            // URL-prefix tag is `swift-org` are indexed; swift-book-tagged
            // pages count toward `skipped` and are picked up by
            // `Search.SwiftBookStrategy` which targets `swift-book.db`.
            try await Search.StrategyHelpers.crawlSwiftDocumentation(
                swiftOrgDirectory: swiftOrgDirectory,
                markdownStrategy: markdownStrategy,
                logger: logger,
                scope: .swiftOrgOnly,
                summarySource: source,
                into: index,
                progress: progress,
                platformVersions: SwiftOrgPlatformResolver()
            )
        }
    }
}

// MARK: - #1097 server-side platform inference

/// Bridges swift-org content-category logic into the shared
/// `crawlSwiftDocumentation` helper. Server-side Swift guides
/// (URI prefix `documentation_server_`) are Linux-deployment
/// content with no Apple-platform applicability — they get NULL
/// `min_<platform>` columns. Everything else (blog posts, articles,
/// install guides, DocC docs) inherits the universal Swift baseline.
// #1116: internal (was private) so the per-resolver tagging behaviour
// can be unit-tested directly.
struct SwiftOrgPlatformResolver: Search.PlatformVersionsResolver {
    func versions(for url: URL) -> Search.PlatformVersions {
        // The URL path encoded the source layout: swift-book/ pages
        // get filename-derived slugs; the rest carry the full
        // path-joined-by-underscores filename. Server-side content
        // sits under `/documentation/server/...` and serialises to
        // filenames starting `documentation_server_`. Check both
        // the URL path itself and the slug-form.
        if isServerSide(url) {
            return Search.PlatformVersions(
                iOS: nil, macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil
            )
        }
        return .universalSwift
    }

    /// #1116: source-specific tag. Pre-fix every resolver-stamped
    /// row carried `"swift-book-chapter"` because the helper had
    /// the label hardcoded. Server-side Linux-deployment rows tag
    /// `swift-org-linux-server`; cross-platform Swift content tags
    /// `swift-org-universal`.
    func availabilitySource(for url: URL) -> String? {
        isServerSide(url) ? "swift-org-linux-server" : "swift-org-universal"
    }

    private func isServerSide(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let slug = url.lastPathComponent.lowercased()
        return path.contains("/documentation/server/") || slug.hasPrefix("documentation_server_")
    }
}
