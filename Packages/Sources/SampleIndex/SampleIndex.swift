import Foundation
import Shared

// MARK: - SampleIndex Namespace

/// SampleIndex provides indexing and search for Apple sample code projects.
/// Unlike the main Search database, SampleIndex uses a separate database
/// (`~/.cupertino/samples.db`) optimized for code-level search.
public enum SampleIndex {
    /// Default database path for source code search index
    public static var defaultDatabasePath: URL {
        Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(Shared.Constants.FileName.samplesDatabase)
    }

    /// Default sample code directory
    public static var defaultSampleCodeDirectory: URL {
        Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(Shared.Constants.Directory.sampleCode)
    }

    /// Map a user-facing platform name (case-insensitive) to the
    /// `projects.min_<x>` column on samples.db. Returns nil for unknown
    /// platforms — caller treats that as "no filter". Mirrors
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
