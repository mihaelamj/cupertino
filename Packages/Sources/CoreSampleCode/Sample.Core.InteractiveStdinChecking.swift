import Foundation
import SharedConstants

// MARK: - Sample.Core.InteractiveStdinChecking

extension Sample.Core {
    /// GoF Strategy (1994 p. 315) seam for "is stdin attached to an
    /// interactive terminal?". Lets `Sample.Core.Downloader` swap the
    /// `isatty(fileno(stdin))` check at the seam instead of mutating a
    /// `nonisolated(unsafe) static var` override from tests.
    ///
    /// Production conformer: `Sample.Core.LiveInteractiveStdinCheck`
    /// (calls `isatty(fileno(stdin))`).
    /// Test conformer: `Sample.Core.StubInteractiveStdinCheck` (returns a
    /// fixed value, declared in this target's tests).
    ///
    /// `Sendable` because the conformer is captured by the
    /// `@MainActor` `Downloader` and a strategy parameter on the
    /// `awaitAuthOutcome` helper; the protocol carries no mutable state.
    public protocol InteractiveStdinChecking: Sendable {
        /// Returns `true` when stdin is an interactive TTY.
        func isInteractive() -> Bool
    }
}
