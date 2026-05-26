import Foundation
import SearchModels
import SharedConstants

// MARK: - AppleDocsSource.fetchInfo

/// Per-source `Search.FetchInfo` literal. Carries the data the CLI's
/// `cupertino fetch --source apple-docs` flow needs (display name,
/// crawl roots, default output dir key). Replaces the corresponding
/// switch arms on the pre-#1007 `FetchType` enum: `displayName`
/// (FetchType.docs), `crawlBaseURLs` (Shared.Constants.BaseURL.appleDeveloperDocs),
/// `defaultOutputDir` (`.docs` key resolved against `Shared.Paths` at
/// composition time), `isWebCrawlable` (true).
extension AppleDocsSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: Shared.Constants.DisplayName.appleDocs,
        sourceID: Shared.Constants.SourcePrefix.appleDocs,
        crawlBaseURLs: [Shared.Constants.BaseURL.appleDeveloperDocs],
        defaultOutputDirKey: .docs,
        isWebCrawlable: true
    )
}
