import EnrichmentModels
import Foundation
import SearchModels

extension Enrichment {
    /// Propagates the generic-constraints map from parent symbols down to
    /// their child methods that carry the same generic placeholder without
    /// re-declaring the constraint. Wraps
    /// `Search.Index.propagateConstraintsFromParents()`.
    ///
    /// Depends on `constraints` so the authoritative Apple-type values
    /// land first; the hierarchy walk then reads from the now-richer
    /// parent map. This matches the historical inline ordering in
    /// `Search.IndexBuilder.buildIndex` (iter 3 before iter 2).
    public final class HierarchyPass: EnrichmentPass {
        public let identifier = "hierarchy"
        public let schemaVersion = 1
        public let dependsOn: [String] = ["constraints"]
        public let target = EnrichmentModels.Target.search

        private let searchIndex: any Search.IndexWriter

        public init(searchIndex: any Search.IndexWriter) {
            self.searchIndex = searchIndex
        }

        public func run(database: OpaquePointer?) async throws -> EnrichmentModels.Result {
            try await searchIndex.propagateConstraintsFromParents()
            return EnrichmentModels.Result(
                passIdentifier: identifier,
                rowsAffected: 0,
                rowsSkipped: 0,
                durationMs: 0
            )
        }
    }
}
