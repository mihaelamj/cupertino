import Foundation
import SearchModels
import SharedConstants

// MARK: - HIGSource.fetchInfo

/// Per-source `Search.FetchInfo` literal. Carries the data the CLI's
/// `cupertino fetch --source hig` flow needs (display name, crawl
/// roots, default output dir key). Replaces the corresponding switch
/// arms on the pre-#1007 `FetchType.hig` enum case in
/// `CLI/SupportingTypes.swift`.
extension HIGSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: Shared.Constants.DisplayName.humanInterfaceGuidelines,
        sourceID: Shared.Constants.SourcePrefix.hig,
        crawlBaseURLs: [Shared.Constants.BaseURL.appleHIG],
        defaultOutputDirKey: .hig,
        isWebCrawlable: true,
        corpusFileSuffix: "pages"
    )
}
