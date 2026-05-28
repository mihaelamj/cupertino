import EnrichmentModels
import Foundation
import SearchModels

extension Enrichment {
    /// Applies the authoritative Apple SDK conformance table to a docs DB's
    /// `doc_symbols.conformances` column. Conformance sibling of
    /// `AppleConstraintsPass`: the lookup is sourced from the cupertino
    /// symbol-graph corpus (`apple-conformances.json`, produced by
    /// `cupertino-constraints-gen conformances`). Routes the call through the
    /// post-index enrichment pipeline.
    public final class AppleConformancesPass: EnrichmentPass {
        public let identifier = "apple-conformances"
        public let schemaVersion = 1
        public let dependsOn: [String] = []
        public let target = EnrichmentModels.Target.search

        private let searchIndex: any Search.IndexWriter
        private let lookup: (any Search.StaticConformancesLookup)?
        private let audit: (any Search.EnrichmentAuditObserver)?
        private let dbPath: String

        /// - Parameters:
        ///   - searchIndex: the docs DB index the pass writes to.
        ///   - lookup: the authoritative conformance table. When nil (no
        ///     symbol-graph corpus wired in) the pass is a no-op and the build
        ///     keeps only the AST-extracted `doc_symbols.conformances`.
        ///   - audit: optional per-entry audit observer.
        ///   - dbPath: tagged into every audit event.
        public init(
            searchIndex: any Search.IndexWriter,
            lookup: (any Search.StaticConformancesLookup)?,
            audit: (any Search.EnrichmentAuditObserver)? = nil,
            dbPath: String = ""
        ) {
            self.searchIndex = searchIndex
            self.lookup = lookup
            self.audit = audit
            self.dbPath = dbPath
        }

        public func run(database _: OpaquePointer?) async throws -> EnrichmentModels.Result {
            guard lookup != nil else {
                return EnrichmentModels.Result(
                    passIdentifier: identifier,
                    rowsAffected: 0,
                    rowsSkipped: 0,
                    durationMs: 0
                )
            }
            let affected = try await searchIndex.applyAppleStaticConformances(
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
