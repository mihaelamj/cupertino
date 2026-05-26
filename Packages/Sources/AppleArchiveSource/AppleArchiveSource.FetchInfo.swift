import Foundation
import SearchModels
import SharedConstants

// MARK: - AppleArchiveSource.fetchInfo

/// Per-source `Search.FetchInfo` literal. Carries the data the CLI's
/// `cupertino fetch --source apple-archive` flow needs. Lifted from
/// the pre-#1007 `FetchType.archive` switch arms in
/// `CLI/SupportingTypes.swift` (displayName from
/// `Shared.Constants.DisplayName.archive`, crawl base URL from
/// `Shared.Constants.BaseURL.appleArchive`, default output dir
/// `.archive`, isWebCrawlable false since archive isn't in
/// `FetchType.webCrawlTypes`).
extension AppleArchiveSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: Shared.Constants.DisplayName.archive,
        sourceID: Shared.Constants.SourcePrefix.appleArchive,
        crawlBaseURLs: [Shared.Constants.BaseURL.appleArchive],
        defaultOutputDirKey: .archive,
        isWebCrawlable: false
    )
}
