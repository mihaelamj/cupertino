import Foundation
import SharedConstants

// MARK: - Sample.Index.SamplesIndexingPhaseObserving

extension Sample.Index {
    /// GoF Observer (1994 p. 293) for sample-indexing lifecycle events.
    /// Replaces the inline `onPhase: @escaping @Sendable (SamplesIndexingPhase) -> Void`
    /// closure parameter previously taken by
    /// `Sample.Index.SamplesIndexingRunner.run`.
    ///
    /// The previous design comment said "the phase callback stays a closure
    /// — it's a genuine lifecycle event stream, not a strategy seam." That
    /// documented choice is reversed here per the standing cupertino rule
    /// "no closures, they ate magic" (see
    /// `mihaela-agents/Rules/swift/gof-di-rules.md` rule 5). A typed
    /// protocol surfaces the operation name, gives the payload a stable
    /// home in the seam target, and lets implementations be discoverable,
    /// mockable, testable, and documented in one place — even when the
    /// call is "genuinely" an event stream rather than a swappable
    /// algorithm.
    public protocol SamplesIndexingPhaseObserving: Sendable {
        /// Called once per lifecycle phase transition during a sample-index
        /// build run. Implementations should be non-blocking; the runner
        /// waits for return before continuing.
        func observe(phase: Sample.Index.SamplesIndexingPhase)
    }
}
