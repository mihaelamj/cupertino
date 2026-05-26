import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftEvolutionSource.fetchInfo

/// Per-source `Search.FetchInfo` literal lifted from the pre-#1007
/// `FetchType.evolution` switch arms. `swift-evolution` is in
/// `FetchType.webCrawlTypes`, so `isWebCrawlable` is true.
extension SwiftEvolutionSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: Shared.Constants.DisplayName.swiftEvolution,
        sourceID: Shared.Constants.SourcePrefix.swiftEvolution,
        crawlBaseURLs: [Shared.Constants.BaseURL.swiftEvolution],
        defaultOutputDirKey: .swiftEvolution,
        isWebCrawlable: true,
        corpusFileSuffix: "proposals"
    )
}
