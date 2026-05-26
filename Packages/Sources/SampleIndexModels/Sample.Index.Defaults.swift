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
    /// `<baseDirectory>/apple-sample-code.db`: the sample-code index
    /// database path, relative to the caller's resolved base directory.
    /// Post-#1037 this is the shared file that ALSO carries
    /// SampleCodeSource's docs_metadata + docs_fts rows; the two
    /// pipelines coexist via per-pipeline schema-version tables (see
    /// `Sample.Index.Database.samples_schema_version` + Search.Index's
    /// PRAGMA user_version). Pre-#1037 binaries used
    /// `Shared.Constants.FileName.samplesDatabase` ("samples.db"); see
    /// `legacySamplesDatabasePath` for the migration-detection accessor
    /// that still resolves the old filename.
    public static func databasePath(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(Shared.Constants.FileName.appleSampleCodeDatabase)
    }

    /// `<baseDirectory>/samples.db`: the legacy pre-#1037 filename for
    /// the sample-code index database. Kept as a separate accessor so
    /// migration code can detect a user with a leftover samples.db on
    /// disk after upgrading to the post-#1037 binary. Production reads
    /// + writes go through `databasePath(baseDirectory:)` which now
    /// resolves to `apple-sample-code.db`.
    public static func legacySamplesDatabasePath(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(Shared.Constants.FileName.samplesDatabase)
    }

    /// `<baseDirectory>/sample-code/` — the sample-code download
    /// directory, relative to the caller's resolved base directory.
    public static func sampleCodeDirectory(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(Shared.Constants.Directory.sampleCode)
    }

    // Deprecated `defaultDatabasePath` / `defaultSampleCodeDirectory`
    // wrappers deleted in #535 phase 11. They routed through
    // `Shared.Constants.defaultBaseDirectory` → `BinaryConfig.shared`,
    // both of which are also gone. Migration: pass an explicit
    // `baseDirectory:` resolved from `Shared.Paths.live().baseDirectory`
    // at the composition root.

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
