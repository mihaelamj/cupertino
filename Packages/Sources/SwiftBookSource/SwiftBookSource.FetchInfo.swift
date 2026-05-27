import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftBookSource.fetchInfo

/// #1093: swift-book is an independently-fetchable source. Pre-#1093
/// it was a view-source over swift-org's crawl
/// (`corpusDirectoryAlias = .swiftOrg`), which meant `cupertino fetch
/// --source swift-org` had to traverse both spaces in one combined
/// pass — slow, and inseparable from each other.
///
/// Post-fix swift-book has its own seed URL
/// (`docs.swift.org/swift-book/...`) and its own corpus directory
/// (`cupertino-fresh/swift-book/`). `cupertino fetch --source
/// swift-book` crawls only the book (~50 pages, fast). `cupertino
/// fetch --source swift-org` no longer traverses the book.
extension SwiftBookSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: "The Swift Programming Language",
        sourceID: Shared.Constants.SourcePrefix.swiftBook,
        crawlBaseURLs: [Shared.Constants.BaseURL.swiftBook],
        defaultOutputDirKey: .swiftBook,
        isWebCrawlable: true,
        corpusFileSuffix: "pages"
    )
}
