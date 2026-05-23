import EnrichmentModels
import Foundation
import SearchModels

extension Enrichment {
    /// #837 stage 1 — populates packages.db's
    /// `package_metadata.apple_imports_json`: JSON array of Apple
    /// framework modules each package imports. Wraps
    /// `Search.PackageIndex.applyAppleImports`.
    public final class PackagesAppleImportsPass: EnrichmentPass {
        public let identifier = "packages-apple-imports"
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
            let affected = try await packages.applyAppleImports(
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
