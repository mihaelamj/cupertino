import Foundation
import SearchModels
import SharedConstants

// MARK: - SampleCodeSource.fetchInfo

/// Per-source `Search.FetchInfo` literal. Carries the data the CLI's
/// `cupertino fetch --source samples` flow needs. Lifted from the
/// pre-#1007 `FetchType.samples` switch arms in
/// `CLI/SupportingTypes.swift` (displayName "Sample Code (GitHub)",
/// no web-crawl base URL because samples are cloned from GitHub,
/// default output dir `.sampleCode`, isWebCrawlable false).
extension SampleCodeSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: "Sample Code (GitHub)",
        sourceID: Shared.Constants.SourcePrefix.samples,
        crawlBaseURLs: [],
        defaultOutputDirKey: .sampleCode,
        isWebCrawlable: false
    )
}
