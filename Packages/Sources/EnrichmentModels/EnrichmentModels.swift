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

/// Coordinator that runs a registered set of `EnrichmentPass` instances in
/// dependency order against the cupertino DBs.
///
/// Lives in the foundation tier so `Search.IndexBuilder` can depend on the
/// protocol without importing the live `Enrichment` package (that would
/// create a Search → Enrichment → Search cycle since Enrichment imports
/// Search for DB access). The composition root constructs the concrete
/// runner (currently `Enrichment.LiveRunner`) and injects it into
/// `IndexBuilder`.
public protocol EnrichmentRunner: Sendable {
    /// Run every registered pass whose `target` matches `target`, in
    /// `dependsOn` topological order. Passes whose dependencies were
    /// skipped (or threw) are themselves skipped with a recorded reason.
    /// Returns the per-pass results in run order.
    func run(target: EnrichmentModels.Target) async throws -> [EnrichmentModels.Result]
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

    /// Run the pass. Implementations MUST be idempotent: re-running against
    /// the same DB at the same `schemaVersion` returns a `Result` with
    /// `rowsAffected == 0` (or close to it).
    ///
    /// The `database` parameter is **advisory**. Stateless passes (e.g. the
    /// ones the standalone `cupertino-postprocessor` binary will open a DB
    /// for) read from it directly. Live passes that hold their own DB-access
    /// objects (e.g. an injected `Search.Index`) receive `nil` and ignore
    /// the parameter.
    func run(database: OpaquePointer?) async throws -> EnrichmentModels.Result
}
