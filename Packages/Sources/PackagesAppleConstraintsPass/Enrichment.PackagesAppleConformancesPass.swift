import EnrichmentModels
import Foundation
import SearchModels

extension Enrichment {
    /// Applies the authoritative Apple SDK conformance table to packages.db's
    /// `package_symbols.conformances`. Conformance sibling of
    /// `PackagesAppleConstraintsPass`; wraps
    /// `Search.PackageIndex.applyAppleStaticConformances`.
    public final class PackagesAppleConformancesPass: EnrichmentPass {
        public let identifier = "packages-apple-conformances"
        public let schemaVersion = 1
        public let dependsOn: [String] = []
        public let target = EnrichmentModels.Target.packages

        private let packages: any Search.PackageWriter
        private let lookup: (any Search.StaticConformancesLookup)?

        public init(packages: any Search.PackageWriter, lookup: (any Search.StaticConformancesLookup)?) {
            self.packages = packages
            self.lookup = lookup
        }

        public func run(database _: OpaquePointer?) async throws -> EnrichmentModels.Result {
            let affected = try await packages.applyAppleStaticConformances(
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
