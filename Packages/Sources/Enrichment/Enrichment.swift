import EnrichmentModels
import Foundation

/// Namespace anchor for the live concrete implementations of the
/// postprocessor pipeline.
///
/// `EnrichmentModels` carries the foundation-only protocol seam
/// (`EnrichmentPass`, `EnrichmentRunner`, `Target`, `Result`). This package
/// holds the live concretes that depend on `Search`, `SampleIndex`, and
/// `CorePackageIndexing` for DB access.
///
/// Subsequent PRs will register concrete passes (`SynonymsPass`,
/// `AppleConstraintsPass`, `HierarchyPass`, `RecoveryPass`) against the
/// runner. This PR ships the runner shell only so the composition root
/// can wire an empty runner into `Search.IndexBuilder` and the existing
/// inline pass calls can move out one by one in follow-ups.
///
/// Tracking: #837, design `docs/design/post-processor.md`.
public enum Enrichment {}
