import Foundation

// MARK: - Core Namespace

/// Namespace for the core crawling / fetching / transforming layer.
///
/// Layout:
/// - `Core.Protocols.*` — protocols (`ContentFetcher`, `ContentTransformer`,
///                       `CrawlerEngine`) and their companion result types
///                       (`FetchResult`, `TransformResult`, `TransformMetadata`).
///                       Also folds in the concrete utilities that ship in the
///                       same SPM target (`Core.PackageIndexing.ExclusionList`,
///                       `Core.PackageIndexing.GitHubCanonicalizer`,
///                       `Core.Protocols.SwiftPackagesCatalog`,
///                       `Core.Protocols.SwiftPackageEntry`) so the namespace
///                       mirrors the folder on disk.
/// - The rest of `Core.*` (`Core.Crawler`, `Core.Parser.*`, `Core.JSONParser.*`,
///   `Core.PackageIndexing.*`, `Core.WKWebCrawler.*`, …) lives in sibling SPM
///   targets and extends this same root from their own files.
public enum Core {
    /// Folder-mirror sub-namespace for the `Sources/CoreProtocols/` SPM target:
    /// protocols, their result-value companions, and the small utilities that
    /// ship alongside them.
    public enum Protocols {}
}
