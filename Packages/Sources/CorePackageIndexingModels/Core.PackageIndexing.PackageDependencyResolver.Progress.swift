import CoreProtocols
import Foundation
import SharedConstants

// MARK: - Core.PackageIndexing.PackageDependencyResolverProgressObserving

extension Core.PackageIndexing {
    /// GoF Observer (1994 p. 293) for
    /// `Core.PackageIndexing.PackageDependencyResolver` progress.
    /// Replaces the inline
    /// `onProgress: (@Sendable (String, Int, Int) -> Void)?` closure
    /// parameter previously taken by `resolveDependencies(seeds:onProgress:)`.
    ///
    /// Payload is three primitives — `packageName`, `processed`, `total` —
    /// so no value-type seam struct is needed (mirrors
    /// `Search.PackageIndexingProgressReporting` from PR #557).
    public protocol PackageDependencyResolverProgressObserving: Sendable {
        /// Called as each seed package is resolved. The `total` value
        /// can grow as new dependencies are discovered during traversal,
        /// so consumers should treat it as an upper-bound estimate
        /// rather than a fixed denominator.
        func observe(packageName: String, processed: Int, total: Int)
    }
}
