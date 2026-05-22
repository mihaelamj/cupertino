import EnrichmentModels
import Foundation
import SearchModels

extension Enrichment {
    /// #837 stage 2 — applies the authoritative Apple-type generic
    /// constraints table to packages.db's
    /// `package_symbols.generic_constraints`. Wraps
    /// `Search.PackageIndex.applyAppleStaticConstraints`.
    public final class PackagesAppleConstraintsPass: EnrichmentPass {
        public let identifier = "packages-apple-constraints"
        public let schemaVersion = 1
        public let dependsOn: [String] = []
        public let target = EnrichmentModels.Target.packages

        private let packages: any Search.PackageWriter
        private let lookup: (any Search.StaticConstraintsLookup)?

        public init(packages: any Search.PackageWriter, lookup: (any Search.StaticConstraintsLookup)?) {
            self.packages = packages
            self.lookup = lookup
        }

        public func run(database: OpaquePointer?) async throws -> EnrichmentModels.Result {
            let affected = try await packages.applyAppleStaticConstraints(
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
