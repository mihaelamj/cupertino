import Foundation

// MARK: - Search.ImportLog

/// Audit-trail record emitted by the indexer for every input file the
/// import pipeline sees, regardless of outcome. The `cupertino save`
/// run writes one ``ImportLogEntry`` per file to its JSONL audit log
/// (`<base>/.cupertino/save-<run-id>.jsonl`); a user inspecting the log
/// after a re-index can reconstruct, file by file, what the indexer
/// did and why.
///
/// `docs/PRINCIPLES.md` principle 3 — "no content lost at the door" —
/// rests on this record. When a row is collapsed as a benign duplicate
/// the log carries the surviving URI in ``duplicateOf``; the dropped
/// source file is still on disk and can be diffed against the chosen
/// variant. When a row is rejected as poison the log carries
/// ``rejectionReason`` so the rejection class is auditable. When a row
/// surfaces as a tier-C collision the log carries ``collisionWith``
/// pointing at the URI it conflicted with.
public extension Search {
    struct ImportLogEntry: Sendable, Codable, Equatable {
        public enum State: String, Sendable, Codable {
            case indexed
            case benignDupTierA
            case benignDupTierB
            case collisionTierC
            case rejectedHTTPErrorTemplate
            case rejectedJSFallback
            case rejectedPlaceholderTitle
            case rejectedURIHelperMiss
            case rejectedNoURL
        }

        /// On-disk path to the source file the indexer read. Always set.
        public let sourceFile: String
        /// The resolved Apple Developer URL the indexer derived from the
        /// source file (post-canonicalisation: lowercase, fragment +
        /// query stripped, `_` → `-` on prose sub-page segments).
        public let resolvedURL: String?
        /// The `apple-docs://…` URI the indexer was about to INSERT.
        /// Always set for `indexed` / `benign*` / `collisionTierC`;
        /// nil for `rejected*` states (no URI was constructed).
        public let uri: String?
        /// What the indexer did with this row.
        public let state: State
        /// For `benignDupTierA` / `benignDupTierB`: the URI the row
        /// was collapsed onto (same value as `uri` — first-arrived
        /// stays in the index). Nil otherwise.
        public let duplicateOf: String?
        /// For `rejected*` states: the rejection category.
        /// Mirrors the `State` cases (`http_error_template` etc.).
        public let rejectionReason: String?
        /// For `collisionTierC`: the URI the row conflicted with at
        /// the door (same as `uri` — both rows share the same URI
        /// after canonicalisation but their canonical titles differ;
        /// see `docs/PRINCIPLES.md` principle 3).
        public let collisionWith: String?

        public init(
            sourceFile: String,
            resolvedURL: String?,
            uri: String?,
            state: State,
            duplicateOf: String? = nil,
            rejectionReason: String? = nil,
            collisionWith: String? = nil
        ) {
            self.sourceFile = sourceFile
            self.resolvedURL = resolvedURL
            self.uri = uri
            self.state = state
            self.duplicateOf = duplicateOf
            self.rejectionReason = rejectionReason
            self.collisionWith = collisionWith
        }
    }

    // MARK: - ImportLogSink

    /// Per-run sink the indexer writes ``ImportLogEntry`` records to.
    /// One entry per input file the strategy sees. Defined as an
    /// async protocol so JSONL flush is non-blocking and concrete
    /// implementations can serialise behind an actor.
    ///
    /// Strategies hold an optional `(any ImportLogSink)?`. When the
    /// composition root passes a concrete (the CLI does, on every
    /// save / dry-run), the strategy emits per-doc records at every
    /// state transition. When the slot is nil (legacy callers, tests
    /// that don't care), the strategy still works — the log is just
    /// not emitted.
    ///
    /// The concrete writing implementation (``Search.JSONLImportLogSink``)
    /// lives in the `Search` target so this protocol can stay in
    /// `SearchModels` with `Foundation`-only deps, keeping the
    /// foundation-tier seam contract intact.
    protocol ImportLogSink: Sendable {
        /// Append a record to the log. Concretes that buffer / batch
        /// internally are free to do so as long as the eventual write
        /// order matches the call order. Strategy callers do not await
        /// completion of the underlying I/O between records.
        func record(_ entry: ImportLogEntry) async
    }
}
