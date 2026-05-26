import EnrichmentModels
import Foundation
import SampleIndexModels
import SearchModels
import SharedConstants

extension Enrichment {
    /// #837 stage 1 — applies the authoritative Apple-type generic
    /// constraints table to samples.db's `file_symbols.generic_constraints`.
    /// Wraps `Sample.Index.Database.applyAppleStaticConstraints`.
    public final class SamplesAppleConstraintsPass: EnrichmentPass {
        public let identifier = "samples-apple-constraints"
        public let schemaVersion = 1
        public let dependsOn: [String] = []
        public let target = EnrichmentModels.Target.samples

        private let samples: any Sample.Index.Writer
        private let lookup: (any Search.StaticConstraintsLookup)?

        public init(samples: any Sample.Index.Writer, lookup: (any Search.StaticConstraintsLookup)?) {
            self.samples = samples
            self.lookup = lookup
        }

        public func run(database: OpaquePointer?) async throws -> EnrichmentModels.Result {
            let affected = try await samples.applyAppleStaticConstraints(
                lookup: lookup,
                enrichmentVersion: schemaVersion
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
