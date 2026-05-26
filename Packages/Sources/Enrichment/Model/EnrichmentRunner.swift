import Foundation

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
