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

/// A single enrichment pass that operates on one of the cupertino DBs.
///
/// Implementations live in the `Enrichment` package (or in a target-specific
/// sibling like `SampleEnrichment`); this protocol stays in the foundation
/// tier so the postprocessor CLI binary can iterate over a registry of
/// passes without importing `Search`.
public protocol EnrichmentPass: Sendable {
    /// Stable identifier used in dependency graphs and idempotency tracking.
    /// Conventionally a short lowercase token: `"synonyms"`, `"constraints"`,
    /// `"hierarchy"`, `"recovery"`.
    var identifier: String { get }

    /// Bumped when the pass's logic changes in a way that requires re-running
    /// against rows that previously ran an older version. Tracked per row
    /// in the `enrichment_version` column on the target DB.
    var schemaVersion: Int { get }

    /// Identifiers of passes that must complete before this pass runs.
    /// The runner topologically sorts the registered passes; cycles fail-fast.
    var dependsOn: [String] { get }

    /// DB this pass operates against. The runner uses this to dispatch the
    /// right SQLite handle.
    var target: EnrichmentModels.Target { get }

    /// Run the pass against an open SQLite handle. Implementations MUST be
    /// idempotent: re-running against the same DB at the same `schemaVersion`
    /// returns a `Result` with `rowsAffected == 0` (or close to it).
    func run(database: OpaquePointer) async throws -> EnrichmentModels.Result
}
