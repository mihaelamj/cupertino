import Foundation
import LoggingModels
import SharedConstants

// MARK: - Distribution.DatabaseHealthCheck (Doctor command per-DB strategy seam)

extension Distribution {
    /// GoF Strategy (1994 p. 315) seam for `cupertino doctor`'s per-DB
    /// health check. Each conformer is responsible for one local
    /// SQLite database; the `Doctor` command iterates a list of
    /// conformers constructed at the composition root, so adding a
    /// fourth DB requires only a new conformer + appending it to the
    /// list (no Doctor-internal edits).
    ///
    /// Pre-#930 `Doctor` had three hardcoded private methods
    /// (`checkSearchDatabase`, `checkSamplesDatabase`,
    /// `checkPackagesDatabase`) each with bespoke verdict policy
    /// (required vs warning-only), bespoke schema-version probe
    /// (PRAGMA vs bundled-version readout vs none), and bespoke
    /// row-count set. Lifting the three into descriptor-driven
    /// conformers preserves every per-DB specialisation while
    /// collapsing the dispatch loop to one iteration.
    ///
    /// The protocol stays foundation-only: the only imports the
    /// protocol surface needs are `Foundation`, `SharedConstants` (for
    /// `Shared.Models.DatabaseDescriptor`), and `LoggingModels` (for
    /// the output-sink seam). Conformers live in the consumer (CLI
    /// today), where they have full access to the concrete probe +
    /// index actor surface they need to render their section.
    public protocol DatabaseHealthCheck: Sendable {
        /// Identity of the database this conformer checks. The
        /// descriptor's `id` / `filename` / `displayName` drive
        /// Doctor's iteration order (callers sort by descriptor.id
        /// when output stability matters) and post-run aggregation
        /// when reports want to address a specific DB by id.
        var descriptor: Shared.Models.DatabaseDescriptor { get }

        /// Whether a failure of this check should fail Doctor's
        /// overall verdict (red exit code, non-zero status). When
        /// `false`, a missing or unreadable DB emits a warning line
        /// while keeping the overall verdict green; this is the
        /// pre-#930 policy for `samples.db` and `packages.db`.
        ///
        /// The protocol carries the policy on the conformer (not on
        /// the descriptor) because requiredness is a Doctor-time
        /// runtime concern, not a property of the descriptor itself:
        /// e.g. a future `cupertino verify` command might treat all
        /// 3 DBs as required while `doctor` keeps the warning-only
        /// stance for 2 of them.
        var isRequired: Bool { get }

        /// Render the per-DB section to the supplied logging
        /// recorder and return whether the check observed a clean
        /// (no-actionable-failure) state. The return value is
        /// orthogonal to `isRequired`:
        ///
        /// - Required conformer + returns `false` → verdict goes
        ///   red.
        /// - Required conformer + returns `true` → verdict
        ///   contribution stays green.
        /// - Warning-only conformer + returns `false` → section
        ///   surfaces the actionable failure in its text; verdict
        ///   stays green (the `isRequired` gate at the Doctor call
        ///   site keeps the bool out of the aggregate AND-fold).
        /// - Warning-only conformer + returns `true` → no
        ///   actionable failure observed; verdict stays green.
        ///
        /// Doctor's aggregate verdict is computed by a loop that
        /// folds `ok && verdict` only when `check.isRequired` is
        /// true:
        ///
        /// ```
        /// for check in checks {
        ///     let ok = await check.run(output: recording)
        ///     if check.isRequired { verdict = ok && verdict }
        /// }
        /// ```
        ///
        /// The bool from a warning-only conformer is informational
        /// for future consumers (a stricter `cupertino verify` could
        /// AND every conformer's result), but Doctor itself never
        /// reads it. A warning-only conformer is therefore free to
        /// return `false` to signal partial degradation; the gate at
        /// the call site, not the conformer, decides whether that
        /// bool reaches the verdict.
        ///
        /// Asynchronous because at least one production conformer
        /// (`Search.Index` opener) opens its DB via an actor.
        /// Conformers with no async work satisfy the requirement by
        /// returning synchronously.
        ///
        /// The `output` recorder is injected so test conformers can
        /// capture lines for byte-identical output assertions; the
        /// production composition root supplies the live recorder
        /// the rest of `cupertino doctor` writes through.
        func run(output: any Logging.Recording) async -> Bool
    }
}
