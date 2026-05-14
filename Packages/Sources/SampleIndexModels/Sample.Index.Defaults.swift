import Foundation
import SharedConstants

// MARK: - Sample.Index static helpers

/// Default paths + small lookup helpers for the sample-code index.
///
/// Lives in `SampleIndexModels` (foundation-only) so consumers can
/// resolve the canonical on-disk locations of `samples.db` and the
/// sample-code download root without importing the concrete
/// `SampleIndex` target. The same pattern applies as the
/// `Search.Database` / `Sample.Index.Reader` protocol seams: shared
/// abstractions and constants live in the Models target; concrete
/// actors live in the producer target.
extension Sample.Index {
    /// Default database path for the sample-code search index
    /// (`~/.cupertino/samples.db` by default).
    public static var defaultDatabasePath: URL {
        Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(Shared.Constants.FileName.samplesDatabase)
    }

    /// Default sample-code download directory
    /// (`~/.cupertino/sample-code/` by default).
    public static var defaultSampleCodeDirectory: URL {
        Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(Shared.Constants.Directory.sampleCode)
    }

    /// Map a user-facing platform name (case-insensitive) to the
    /// `projects.min_<x>` column on `samples.db`. Returns nil for
    /// unknown platforms — caller treats that as "no filter". Mirrors
    /// `Search.PackageQuery.minColumn` for cross-DB consistency.
    public static func minColumn(for platform: String) -> String? {
        switch platform.lowercased() {
        case "ios": return "min_ios"
        case "macos", "osx", "mac": return "min_macos"
        case "tvos": return "min_tvos"
        case "watchos": return "min_watchos"
        case "visionos": return "min_visionos"
        default: return nil
        }
    }
}
