import EnrichmentModels
import Foundation
import SampleIndexModels
import SearchModels
import SharedConstants

extension Enrichment {
    /// Applies the authoritative Apple SDK conformance table to samples.db's
    /// `file_symbols.conformances`. Conformance sibling of
    /// `SamplesAppleConstraintsPass`; wraps
    /// `Sample.Index.Database.applyAppleStaticConformances`.
    public final class SamplesAppleConformancesPass: EnrichmentPass {
        public let identifier = "samples-apple-conformances"
        public let schemaVersion = 1
        public let dependsOn: [String] = []
        public let target = EnrichmentModels.Target.samples

        private let samples: any Sample.Index.Writer
        private let lookup: (any Search.StaticConformancesLookup)?

        public init(samples: any Sample.Index.Writer, lookup: (any Search.StaticConformancesLookup)?) {
            self.samples = samples
            self.lookup = lookup
        }

        public func run(database _: OpaquePointer?) async throws -> EnrichmentModels.Result {
            let affected = try await samples.applyAppleStaticConformances(
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
