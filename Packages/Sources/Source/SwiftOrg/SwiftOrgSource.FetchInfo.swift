import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftOrgSource.fetchInfo

/// Per-source `Search.FetchInfo` literal lifted from the pre-#1007
/// `FetchType.swift` switch arms in `CLI/SupportingTypes.swift`.
/// `swift-org` IS in `FetchType.webCrawlTypes`, so `isWebCrawlable`
/// is true.
extension SwiftOrgSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: Shared.Constants.DisplayName.swiftOrgDocs,
        sourceID: Shared.Constants.SourcePrefix.swiftOrg,
        crawlBaseURLs: [Shared.Constants.BaseURL.swiftOrg],
        defaultOutputDirKey: .swiftOrg,
        isWebCrawlable: true
    )
}
