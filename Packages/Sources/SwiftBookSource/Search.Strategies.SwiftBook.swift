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
                progress: progress,
                platformVersions: SwiftBookChapterVersionsResolver()
            )
        }
    }
}

// MARK: - #1095 chapter-version resolver

/// Bridges the per-chapter `SwiftBookChapterVersions` table into the
/// shared `crawlSwiftDocumentation` helper. Looks up each page's
/// URL slug (last path component) and returns the matching
/// `Search.PlatformVersions`. Chapters not in the table fall back
/// to the universal Swift baseline via
/// `SwiftBookChapterVersions.floor(forSlug:)`'s default.
// #1103: internal (not private) so the resolver's slug extraction
// + version lookup can be unit-tested via @testable import without
// going through the full crawl helper. The type otherwise isn't
// part of SwiftBookSource's public surface.
struct SwiftBookChapterVersionsResolver: Search.PlatformVersionsResolver {
    func versions(for url: URL) -> Search.PlatformVersions {
        let floor = SwiftBookChapterVersions.floor(forSlug: slug(from: url))
        return Search.PlatformVersions(
            iOS: floor.iOS,
            macOS: floor.macOS,
            tvOS: floor.tvOS,
            watchOS: floor.watchOS,
            visionOS: floor.visionOS
        )
    }

    /// #1103: stamp the chapter's Swift toolchain version into
    /// `implementation_swift_version`. Chapters not in the per-
    /// chapter override table return nil (universal baseline has
    /// no useful version tag).
    func implementationSwiftVersion(for url: URL) -> String? {
        SwiftBookChapterVersions.floor(forSlug: slug(from: url)).swiftVersion
    }

    /// #1116: tag every resolver-stamped swift-book row as
    /// `swift-book-chapter`. Pre-#1116 this string was hardcoded
    /// in `crawlSwiftDocumentation` and got incorrectly applied to
    /// swift-org rows that share the helper's per-page-resolver
    /// path. Per-resolver tagging puts the source-specific label
    /// next to the source-specific lookup.
    func availabilitySource(for _: URL) -> String? {
        "swift-book-chapter"
    }

    private func slug(from url: URL) -> String {
        var slug = url.lastPathComponent
        if slug.isEmpty {
            slug = url.deletingLastPathComponent().lastPathComponent
        }
        if slug.hasSuffix(".html") {
            slug = String(slug.dropLast(".html".count))
        }
        return slug
    }
}
