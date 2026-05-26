import Foundation

/// A single enrichment pass that operates on one of the cupertino DBs.
///
/// Implementations live in per-pass SPM sibling targets (per #906:
/// `AppleConstraintsPass`, `HierarchyPass`, etc.) so each conformer
/// is its own standalone-portable unit. This protocol stays in the
/// foundation tier so the postprocessor CLI binary can iterate over
/// a registry of passes without importing `Search`.
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
