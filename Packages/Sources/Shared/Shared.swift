import Foundation

// MARK: - Shared Namespace

/// Namespace for cross-cutting types shared between every SPM target in the
/// monorepo. Each sub-namespace mirrors one folder under `Sources/Shared/`:
///
/// - `Shared.Constants.*` — `Sources/Shared/Constants/` (paths, file names,
///                          URL patterns, limits, MCP defaults,
///                          `BinaryConfig`).
/// - `Shared.Utils.*`     — `Sources/Shared/Utils/` (Shared.Utils.JSONCoding, Shared.Utils.PathResolver,
///                          Formatting, FTSQuery, SchemaVersion, URL helpers).
/// - `Shared.Models.*`    — `Sources/Shared/Models/` (crawl + document +
///                          package data structures, cleanup result /
///                          statistics types, URL utilities).
///
/// The `Configuration/` and `Core/` subfolders stay flat under `Shared` for
/// now — `Shared.Configuration` is already a top-level aggregate struct (the
/// bundle of CrawlerConfiguration + ChangeDetectionConfiguration + Output)
/// and renaming it requires deciding what to call the existing aggregate;
/// that lands in a follow-up.
public enum Shared {
    /// Cupertino-wide constants: paths, file names, URL patterns, limits,
    /// MCP defaults, plus `Shared.Constants.BinaryConfig` for the
    /// next-to-binary JSON config file.
    public enum Constants {}

    /// Pure utility namespaces (`Shared.Utils.JSONCoding`, `Shared.Utils.PathResolver`, `Formatting`,
    /// `FTSQuery`, `SchemaVersion`). Each is itself a caseless enum.
    public enum Utils {}

    /// Cross-cutting data structures used by crawler, indexer, search, MCP,
    /// and the CLI. Most are `Codable` value types serialised to disk.
    public enum Models {}
}
