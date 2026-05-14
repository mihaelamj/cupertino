import Foundation
import SharedConstants

// MARK: - Sample.Index helpers

/// Path-builder helpers + small lookups for the sample-code index.
///
/// Lives in `SampleIndexModels` (foundation-only) so consumers can
/// resolve the canonical on-disk locations of `samples.db` and the
/// sample-code download root without importing the concrete
/// `SampleIndex` target.
///
/// **Strict DI shape** (post-#535): the old `defaultDatabasePath` /
/// `defaultSampleCodeDirectory` static accessors reached for
/// `Shared.Constants.defaultBaseDirectory` (a Service Locator backed by
/// the `BinaryConfig.shared` Singleton). Replaced with explicit
/// `baseDirectory:` parameters — every caller passes a base directory
/// it owns (typically derived from a `Shared.Paths` value resolved at
/// the composition root).
extension Sample.Index {
    /// `<baseDirectory>/samples.db` — the sample-code search index
    /// database path, relative to the caller's resolved base directory.
    public static func databasePath(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(Shared.Constants.FileName.samplesDatabase)
    }

    /// `<baseDirectory>/sample-code/` — the sample-code download
    /// directory, relative to the caller's resolved base directory.
    public static func sampleCodeDirectory(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(Shared.Constants.Directory.sampleCode)
    }

    /// Legacy static accessor — kept temporarily during the path-DI arc
    /// (#535) so existing callers keep compiling while they're migrated
    /// one at a time to `databasePath(baseDirectory:)`. Reaches for
    /// `Shared.Constants.defaultBaseDirectory` (which itself reaches for
    /// the `BinaryConfig.shared` Singleton); both are scheduled for
    /// deletion at the end of the arc.
    @available(*, deprecated, message: "Path-DI migration (#535): use Sample.Index.databasePath(baseDirectory:) with an explicit base directory threaded from the composition root.")
    public static var defaultDatabasePath: URL {
        Self.databasePath(baseDirectory: Shared.Constants.defaultBaseDirectory)
    }

    /// Legacy static accessor — see `defaultDatabasePath` for the
    /// migration plan. Scheduled for deletion at the end of #535.
    @available(*, deprecated, message: "Path-DI migration (#535): use Sample.Index.sampleCodeDirectory(baseDirectory:) with an explicit base directory threaded from the composition root.")
    public static var defaultSampleCodeDirectory: URL {
        Self.sampleCodeDirectory(baseDirectory: Shared.Constants.defaultBaseDirectory)
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
