import CoreProtocols
import Foundation

// MARK: - Core.PackageIndexing.availabilityFilename

/// Canonical filename for the per-package availability sidecar JSON written
/// alongside `manifest.json` (see `Core.PackageIndexing.PackageAvailabilityAnnotator`
/// for the writer; `Search.PackageIndexer` reads it on the index pass).
///
/// Previously a `public static let outputFilename` on the
/// `PackageAvailabilityAnnotator` actor. Lifted to a free constant in this
/// `CorePackageIndexingModels` target so the call site in `Search.PackageIndexer`
/// can reference it without importing the full `CorePackageIndexing` target.
extension Core.PackageIndexing {
    public static let availabilityFilename = "availability.json"
}
