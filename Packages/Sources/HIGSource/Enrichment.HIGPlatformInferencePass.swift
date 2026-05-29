import EnrichmentModels
import Foundation
import SearchModels

extension Enrichment {
    /// HIG-specific topic-aware platform-inference enrichment pass.
    /// For rows whose URI declares an explicit platform target
    /// (designing-for-watchos, spatial-layout, mac-catalyst, carplay,
    /// etc.), NULLs the `min_<platform>` columns for non-applicable
    /// platforms. Cross-platform topics (the bulk of HIG: buttons,
    /// alerts, accessibility, layout, color) keep their defaults.
    ///
    /// Wraps `Search.Index.applyHIGPlatformInference()`. Pre-fix the
    /// HIG indexer stamped every row with the earliest possible
    /// version of every Apple platform as a baseline default, so
    /// `cupertino search hig --min-ios 16` returned watchOS- and
    /// visionOS-only HIG pages too. This pass corrects that for the
    /// obviously platform-specific subset.
    ///
    /// Target: `.search` (operates on the docs-tier per-source DB
    /// schema; only fires for the HIG provider since the composition
    /// root scopes the pass list to that destination).
    public final class HIGPlatformInferencePass: EnrichmentPass {
        public let identifier = "hig-platforms"
        public let schemaVersion = 1
        public let dependsOn: [String] = []
        public let target = EnrichmentModels.Target.search

        private let searchIndex: any Search.IndexWriter
        private let audit: (any Search.EnrichmentAuditObserver)?
        private let dbPath: String

        public init(
            searchIndex: any Search.IndexWriter,
            audit: (any Search.EnrichmentAuditObserver)? = nil,
            dbPath: String = ""
        ) {
            self.searchIndex = searchIndex
            self.audit = audit
            self.dbPath = dbPath
        }

        public func run(database _: OpaquePointer?) async throws -> EnrichmentModels.Result {
            let affected = try await searchIndex.applyHIGPlatformInference(
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
