import Foundation

/// Foundation-only seam for the cupertino postprocessor pipeline.
///
/// Defines the protocol every enrichment pass conforms to plus the value types
/// passes emit. Lives in its own target so the postprocessor binary (a separate
/// layer per epic #769) and the live implementations in the `Enrichment`
/// package can both build against the same protocol without dragging in
/// `Search`, `SampleIndex`, or `CorePackageIndexing`. Dependencies are empty
/// by design; the live concrete passes link the DB-specific packages.
///
/// Design reference: `docs/design/post-processor.md`.
/// Tracking issue: #837.
public enum EnrichmentModels {
    /// Which database an enrichment pass targets. Each backing DB
    /// (`search.db`, `samples.db`, `packages.db`) is a separate target so
    /// the runner can route passes to the right database without the pass
    /// having to know its execution context.
    public enum Target: String, Sendable, Hashable, CaseIterable {
        case search
        case samples
        case packages
    }

    /// Result of running a single enrichment pass.
    public struct Result: Sendable, Hashable {
        /// Matches `EnrichmentPass.identifier` of the pass that produced this.
        public let passIdentifier: String

        /// Rows the pass wrote / updated.
        public let rowsAffected: Int

        /// Rows the pass examined and skipped (already at current
        /// `enrichment_version`, or no eligible data).
        public let rowsSkipped: Int

        /// Wall-clock milliseconds the pass ran for.
        public let durationMs: Int

        public init(passIdentifier: String, rowsAffected: Int, rowsSkipped: Int, durationMs: Int) {
            self.passIdentifier = passIdentifier
            self.rowsAffected = rowsAffected
            self.rowsSkipped = rowsSkipped
            self.durationMs = durationMs
        }
    }
}
