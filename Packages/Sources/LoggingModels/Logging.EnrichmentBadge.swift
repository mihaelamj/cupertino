import Foundation

// MARK: - Logging enrichment badge

extension Logging {
    /// Paths to the enrichment INPUT files the active DB's enrichment
    /// passes will read at the END of the save (e.g. apple-constraints.json,
    /// apple-conformances.json). Bound per-DB by the save command around the
    /// index build; read by ``enrichmentBadge()`` on each progress line.
    ///
    /// `nil` for DBs that declare no enrichment inputs (no input-gated
    /// enrichment to report). A `@TaskLocal` because the progress lines are
    /// emitted deep inside the source strategies via the shared recorder, and
    /// `Search.IndexBuilder.buildIndex` runs each strategy with a plain
    /// `await` (no detached task), so a value bound around the build
    /// propagates into the emission with no per-strategy plumbing.
    @TaskLocal public static var enrichmentInputPaths: [String]?

    /// Live enrichment-status badge for an indexing progress line:
    ///
    /// - `🧬` every declared input file is present (the enrichment pass will
    ///   run when indexing finishes),
    /// - `🚫 no-enrich` at least one is missing (the save proceeds best-effort
    ///   and the DB is built un-enriched),
    /// - `nil` the active DB declares no enrichment inputs.
    ///
    /// Existence is re-checked on every call, so the badge flips `🚫`→`🧬`
    /// the moment an operator produces a missing file mid-save (the input is
    /// not read until the enrichment phase, so it is still picked up).
    public static func enrichmentBadge() -> String? {
        guard let paths = enrichmentInputPaths, !paths.isEmpty else {
            return nil
        }
        let allPresent = paths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
        return allPresent ? "🧬" : "🚫 no-enrich"
    }
}
