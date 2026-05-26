import Foundation

/// Namespace anchor for the enrichment-pass concretes and seams.
///
/// Pre-#906 sub-PR B the `Enrichment` enum lived in the Enrichment
/// producer target. #906 sub-PR B moves the anchor here (mirroring
/// the `Search` / `Crawler` / `SampleIndex` / `Availability` Models-as-anchor
/// pattern) so per-pass sibling targets can extend `Enrichment.<X>Pass`
/// without depending on the Enrichment producer concrete.
public enum Enrichment {
    // Namespace root; concretes live in per-pass SPM siblings + the
    // Enrichment producer for orchestration code (LiveRunner).
}
