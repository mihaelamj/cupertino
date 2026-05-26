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
///
/// Post-#1042 type-name deepening: the legacy top-level `EnrichmentModels`
/// enum is now a nested namespace `Enrichment.Model`. Consumers' import
/// stays `import EnrichmentModels` (SPM target identity preserved); only
/// the Swift type path changes (`EnrichmentModels.Target` ->
/// `Enrichment.Model.Target`). A `public typealias EnrichmentModels =
/// Enrichment.Model` keeps existing call-sites compiling until they
/// migrate.
extension Enrichment {
    public enum Model {
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
            /// `enrichment_version`, or no eligible data). SET-based UPDATE
            /// passes (e.g. constraints, hierarchy) report 0 here. only
            /// row-iteration passes that filter by `enrichment_version`
            /// populate it.
            public let rowsSkipped: Int

            /// Wall-clock milliseconds the pass ran for. A pass may return 0
            /// as a sentinel. `Enrichment.LiveRunner` measures the elapsed
            /// time and patches the result before surfacing it. So callers
            /// always observe a non-zero value for non-trivial passes even
            /// when the pass left this field blank.
            public let durationMs: Int

            public init(passIdentifier: String, rowsAffected: Int, rowsSkipped: Int, durationMs: Int) {
                self.passIdentifier = passIdentifier
                self.rowsAffected = rowsAffected
                self.rowsSkipped = rowsSkipped
                self.durationMs = durationMs
            }
        }
    }
}

/// Back-compat alias for pre-#1042 consumers. Existing code that
/// references `EnrichmentModels.Target` keeps compiling; new code uses
/// `Enrichment.Model.Target` directly.
public typealias EnrichmentModels = Enrichment.Model
