import Foundation
import SearchModels
import SharedConstants

// MARK: - PackagesSource.fetchInfo

/// Per-source `Search.FetchInfo` literal lifted from the pre-#1007
/// `FetchType.packages` switch arms in `CLI/SupportingTypes.swift`.
/// Empty `crawlBaseURLs` because the packages fetch is API-based +
/// GitHub archive download, not a URL crawl; `isWebCrawlable false`
/// because `packages` is not in `FetchType.webCrawlTypes`.
extension PackagesSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: Shared.Constants.DisplayName.swiftPackages,
        sourceID: Shared.Constants.SourcePrefix.packages,
        crawlBaseURLs: [],
        defaultOutputDirKey: .packages,
        isWebCrawlable: false
    )
}
