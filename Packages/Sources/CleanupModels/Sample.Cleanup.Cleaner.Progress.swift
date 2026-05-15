import Foundation
import SharedConstants

// MARK: - Sample.Cleanup.CleanerProgressObserving
//
// Naming note: the producer-target `Sample.Cleanup.Cleaner` is a
// `public actor` declared in the `Cleanup` SPM target's
// `Sample.Cleanup.Cleaner.swift`. To keep its Observer protocol in
// this foundation-only seam target (so any conformer can implement
// without `import Cleanup`), the protocol uses a flat name under
// `Sample.Cleanup` (`CleanerProgressObserving`) rather than nested
// under the actor. Same pattern as the crawler / CorePackageIndexing
// seam protocols.
//
// `Sample.Cleanup` namespace anchor lives in `SharedConstants`
// (`Packages/Sources/Shared/Sample.swift`). This file extends it.

extension Sample.Cleanup {
    /// GoF Observer (1994 p. 293) for `Sample.Cleanup.Cleaner.cleanup`
    /// progress. Replaces the previous inline
    /// `onProgress: (@Sendable (Shared.Models.CleanupProgress) -> Void)?`
    /// closure parameter. Per the standing cupertino rule "no closures,
    /// they ate magic."
    ///
    /// Payload is `Shared.Models.CleanupProgress` (already in foundation-
    /// tier `SharedConstants`), so this protocol is fully foundation-
    /// only. Any test conformer needs only `import CleanupModels` plus
    /// `import SharedConstants` for the payload type.
    public protocol CleanerProgressObserving: Sendable {
        /// Called periodically as each archive is processed.
        /// Implementations should be non-blocking; the cleaner waits
        /// for return before continuing to the next archive.
        func observe(progress: Shared.Models.CleanupProgress)
    }
}
