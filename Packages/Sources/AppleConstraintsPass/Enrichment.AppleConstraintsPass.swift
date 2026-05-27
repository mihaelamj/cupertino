import EnrichmentModels
import Foundation
import SearchModels

extension Enrichment {
    /// Applies the authoritative Apple-type generic-constraints table to
    /// `search.db`. The constraints lookup is sourced from cupertino's
    /// symbolgraph corpus (the cupertino-symbolgraphs companion repo,
    /// surfaced via `AppleConstraintsKit`); see #759 iteration 3 for the
    /// original design.
    ///
    /// Wraps `Search.Index.applyAppleStaticConstraints(lookup:)` so the
    /// existing SQL implementation stays where it is in
    /// `Search.Index.AppleStaticConstraints.swift`. This pass exists to
    /// route the call through the postprocessor pipeline.
    public final class AppleConstraintsPass: EnrichmentPass {
        public let identifier = "constraints"
        public let schemaVersion = 1
        public let dependsOn: [String] = []
        public let target = EnrichmentModels.Target.search

        private let searchIndex: any Search.IndexWriter
        private let lookup: (any Search.StaticConstraintsLookup)?
        private let audit: (any Search.EnrichmentAuditObserver)?
        private let dbPath: String

        /// - Parameters:
        ///   - searchIndex: the search.db index the pass writes to.
        ///   - lookup: the authoritative constraints table. When nil
        ///     (no symbolgraph corpus wired in at the composition root)
        ///     the pass is a no-op and the build falls back to the
        ///     iter 1 + iter 2 inline constraint extraction alone.
        ///   - audit: optional per-entry audit observer. Emits
        ///     `recordPassStart` / `recordEntry` (per matched URI) /
        ///     `recordPassEnd` so the composition root can write a JSONL
        ///     audit trail.
        ///   - dbPath: tagged into every audit event so a single log
        ///     file carries events from multiple per-source DBs in the
        ///     same save run.
        public init(
            searchIndex: any Search.IndexWriter,
            lookup: (any Search.StaticConstraintsLookup)?,
            audit: (any Search.EnrichmentAuditObserver)? = nil,
            dbPath: String = ""
        ) {
            self.searchIndex = searchIndex
            self.lookup = lookup
            self.audit = audit
            self.dbPath = dbPath
        }

        public func run(database: OpaquePointer?) async throws -> EnrichmentModels.Result {
            guard lookup != nil else {
                return EnrichmentModels.Result(
                    passIdentifier: identifier,
                    rowsAffected: 0,
                    rowsSkipped: 0,
                    durationMs: 0
                )
            }
            let affected = try await searchIndex.applyAppleStaticConstraints(
                lookup: lookup,
                audit: audit,
                dbPath: dbPath
            )
            return EnrichmentModels.Result(
                passIdentifier: identifier,
                rowsAffected: affected,
                rowsSkipped: 0,
                durationMs: 0
            )
        }
    }
}
