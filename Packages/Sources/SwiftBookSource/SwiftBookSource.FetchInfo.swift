import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftBookSource.fetchInfo

/// #1082: swift-book is a view-source over the swift-org crawl —
/// its pages live under the swift-org corpus directory. Pre-fix
/// `fetchInfo` was nil and `requiresCorpusDirectory` was `false`,
/// which routed `SwiftBookStrategy` to a `/dev/null` placeholder
/// (since the resolver had no per-source-directory entry for it).
/// The strategy then walked an empty dir and returned
/// `(0, 0, wasSkipped: true, "no documents found")`, leaving
/// `swift-book.db` empty.
///
/// Post-fix `fetchInfo` declares `defaultOutputDirKey = .swiftOrg`
/// so the CLI's `directoryByKey` dict maps `"swift-book"` to
/// `paths.swiftOrgDirectory`. `SwiftBookStrategy` then walks the
/// real swift-org tree, applies its `.swiftBookOnly` scope filter,
/// and emits the swift-book-tagged pages into `swift-book.db`.
///
/// `crawlBaseURLs` carries both swift.org roots so a fetch
/// invocation (`cupertino fetch --source swift-book`) crawls the
/// shared swift-org seed pages and discovers swift-book pages via
/// the URL-prefix tagging the crawler already does.
extension SwiftBookSource {
    public static let fetchInfo: Search.FetchInfo = .init(
        displayName: Shared.Constants.DisplayName.swiftBook,
        sourceID: Shared.Constants.SourcePrefix.swiftBook,
        crawlBaseURLs: [
            Shared.Constants.BaseURL.swiftOrg,
            Shared.Constants.BaseURL.swiftBook,
        ],
        defaultOutputDirKey: .swiftOrg,
        isWebCrawlable: true,
        corpusFileSuffix: "pages"
    )
}
