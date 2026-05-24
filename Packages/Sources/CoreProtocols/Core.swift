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
/// - The rest of `Core.*` lives in sibling SPM targets and extends
///   this same root from their own files:
///   `Core.Parser.*` (HTML / XML transformers) in `Core`;
///   `Core.JSONParser.*` (DocC JSON pipeline) in `CoreJSONParser` +
///   `Core.JSONParser.WKWebViewTitleFetcher` in `CoreJSONParserWebKit`
///   (#904); `Core.PackageIndexing.*` in `CorePackageIndexing`.
public enum Core {
    /// Folder-mirror sub-namespace for the `Sources/CoreProtocols/` SPM target:
    /// protocols, their result-value companions, and the small utilities that
    /// ship alongside them.
    public enum Protocols {}

    /// Sub-namespace anchor for the `CoreJSONParser` SPM target and its
    /// `CoreJSONParserWebKit` sibling. The actual types live in those
    /// producers; this anchor lives in CoreProtocols (foundation tier) so
    /// the sibling target can extend `Core.JSONParser.*` without
    /// importing the parent producer (#904 strict-DI seam).
    public enum JSONParser {}
}
