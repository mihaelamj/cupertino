import Foundation

// MARK: - Search.DocKind

extension Search {
    /// High-level document-shape taxonomy stored per row in
    /// `docs_metadata.kind`. Stored as `TEXT NOT NULL DEFAULT 'unknown'`.
    /// Consumed by the smart-query wrapper to route queries per-intent.
    ///
    /// The taxonomy is deterministic: a pure function of `source`,
    /// `structuredKind`, and URI path. No AI, no runtime state.
    ///
    /// **Post-#1045 Gap 3**: lifted from `SearchSQLite/DocKind.swift`
    /// into SearchModels (foundation tier) so `Search.SourceProvider`
    /// can declare `func docKind(structuredKind:uriPath:) -> Search.DocKind`
    /// — each per-source target owns its own classifier, replacing the
    /// 6-arm `switch source` in `Search.Classify.kind`. The Classify
    /// dispatcher now reads from the registry instead of the switch.
    public enum DocKind: String, Codable, Sendable, CaseIterable {
        /// API reference with a declaration (struct/class/protocol/enum/func/etc.).
        case symbolPage
        /// Discussion, overview, or collection index page.
        case article
        /// DocC tutorial chapter or step.
        case tutorial
        /// Apple sample-code landing page.
        case sampleCode
        /// Swift Evolution proposal.
        case evolutionProposal
        /// The Swift Programming Language book.
        case swiftBook
        /// Other Swift.org documentation.
        case swiftOrgDoc
        /// Human Interface Guidelines page.
        case hig
        /// Legacy Apple Archive programming guide.
        case archive
        /// Fallback — classifier had no matching branch (or source
        /// has no SourceProvider registered, or the registered provider
        /// uses the default protocol extension).
        case unknown
    }
}
