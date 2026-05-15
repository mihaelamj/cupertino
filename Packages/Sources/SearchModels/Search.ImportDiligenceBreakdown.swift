import Foundation

// MARK: - Search.ImportDiligenceBreakdown

/// Per-strategy / per-run breakdown of the #588 import-diligence
/// classifications: door equivalence outcomes (tier A / B / C) plus
/// pre-INSERT garbage filter rejections by category.
///
/// All counters are subsets of the underlying `Search.IndexStats.skipped`
/// total — they classify the rejection reason, they don't add new
/// rejections. A value of zero everywhere means either:
///
/// 1. The strategy didn't run the #588 door + garbage gates (HIG,
///    SwiftEvolution, SwiftOrg, AppleArchive, SampleCode all leave the
///    breakdown at default zero), OR
/// 2. The strategy did run them and the input was perfectly clean.
///
/// **Definition of Done for `cupertino save` against the canonical
/// corpus: `tierCCollisionCount == 0`** per `docs/PRINCIPLES.md`
/// principle 3.
public extension Search {
    struct ImportDiligenceBreakdown: Sendable, Equatable {
        /// Tier A — identical content hash; same bytes; silent collapse.
        public let benignDupTierA: Int
        /// Tier B — same canonical title, drifted content hash; same
        /// logical Apple page rendered slightly differently between
        /// crawls; first-arrived wins.
        public let benignDupTierB: Int
        /// Tier C — different canonical title at the same URI; the URI
        /// canonicalisation conflated two distinct Apple pages.
        /// **Must be 0 for DoD.**
        public let tierCCollisionCount: Int
        /// Pre-INSERT garbage filter — page title matched an HTTP error
        /// template pattern (#284 indexer defence).
        public let rejectedHTTPErrorTemplate: Int
        /// Pre-INSERT garbage filter — page body matched the JS-disabled
        /// fallback signature (#284 indexer defence).
        public let rejectedJSFallback: Int
        /// Pre-INSERT garbage filter — page title matched the bare
        /// "Error" / "Apple Developer Documentation" placeholder Apple's
        /// JS app emits on a failed data fetch (#588 indexer defence).
        public let rejectedPlaceholderTitle: Int

        public init(
            benignDupTierA: Int = 0,
            benignDupTierB: Int = 0,
            tierCCollisionCount: Int = 0,
            rejectedHTTPErrorTemplate: Int = 0,
            rejectedJSFallback: Int = 0,
            rejectedPlaceholderTitle: Int = 0
        ) {
            self.benignDupTierA = benignDupTierA
            self.benignDupTierB = benignDupTierB
            self.tierCCollisionCount = tierCCollisionCount
            self.rejectedHTTPErrorTemplate = rejectedHTTPErrorTemplate
            self.rejectedJSFallback = rejectedJSFallback
            self.rejectedPlaceholderTitle = rejectedPlaceholderTitle
        }

        /// All-zero breakdown — convenience for strategies that don't
        /// classify (HIG, SwiftEvolution, SwiftOrg, AppleArchive, SampleCode).
        public static let zero = ImportDiligenceBreakdown()

        /// True iff every counter is zero. Useful for guarding the
        /// "import diligence" block in the save final report so non-
        /// apple-docs builds keep their original summary shape.
        public var isEmpty: Bool {
            benignDupTierA == 0
                && benignDupTierB == 0
                && tierCCollisionCount == 0
                && rejectedHTTPErrorTemplate == 0
                && rejectedJSFallback == 0
                && rejectedPlaceholderTitle == 0
        }

        /// Element-wise sum. Used by the CLI to aggregate per-strategy
        /// breakdowns into a single per-build report.
        public static func + (lhs: ImportDiligenceBreakdown, rhs: ImportDiligenceBreakdown) -> ImportDiligenceBreakdown {
            ImportDiligenceBreakdown(
                benignDupTierA: lhs.benignDupTierA + rhs.benignDupTierA,
                benignDupTierB: lhs.benignDupTierB + rhs.benignDupTierB,
                tierCCollisionCount: lhs.tierCCollisionCount + rhs.tierCCollisionCount,
                rejectedHTTPErrorTemplate: lhs.rejectedHTTPErrorTemplate + rhs.rejectedHTTPErrorTemplate,
                rejectedJSFallback: lhs.rejectedJSFallback + rhs.rejectedJSFallback,
                rejectedPlaceholderTitle: lhs.rejectedPlaceholderTitle + rhs.rejectedPlaceholderTitle
            )
        }
    }
}
