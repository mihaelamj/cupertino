import Foundation

// MARK: - Search.PlatformVersionsResolver

extension Search {
    /// #1095: per-page platform-version override seam. Strategies
    /// that need page-specific platform floors (e.g. swift-book's
    /// per-chapter Swift-version table) supply a conformer to the
    /// shared `crawlSwiftDocumentation` helper, which calls
    /// `versions(for:)` for each indexed page and stamps the
    /// returned tuple onto the indexer's `overrideMin<Platform>`
    /// parameters.
    ///
    /// Default behaviour (when the strategy passes `nil`) is the
    /// universal Swift baseline (iOS 8.0 / macOS 10.9 / tvOS 9.0 /
    /// watchOS 2.0 / visionOS 1.0).
    ///
    /// Per `mihaela-agents/Rules/swift/gof-di-rules.md` rule 4: this
    /// is a protocol seam, not a closure typealias. Each strategy
    /// has its own conformer that owns the lookup logic.
    public protocol PlatformVersionsResolver: Sendable {
        /// Per-page platform-version floor. Returned tuple values
        /// land on `Search.IndexWriter.indexStructuredDocument`'s
        /// `overrideMin<Platform>` parameters. `nil` for a platform
        /// means "stamp NULL on that column".
        func versions(for url: URL) -> Search.PlatformVersions

        /// #1103: per-page Swift toolchain version, stamped onto
        /// `docs_metadata.implementation_swift_version`. Sister
        /// signal to `versions(for:)` for sources where a page
        /// requires a known Swift version (swift-book's
        /// concurrency/macros chapters; future swift-org content
        /// can opt in the same way). `nil` means "stamp NULL".
        /// Default implementation returns nil so existing conformers
        /// don't need to change.
        func implementationSwiftVersion(for url: URL) -> String?

        /// #1116: per-page `availability_source` tag, stamped onto
        /// `docs_metadata.availability_source`. Source-specific
        /// label so consumers can tell swift-org from swift-book
        /// rows (pre-#1116 every resolver-stamped row was hardcoded
        /// to `"swift-book-chapter"`, mislabelling swift-org pages).
        /// Conformers should return a stable string keyed on the
        /// source-id, e.g. `"swift-book-chapter"`, `"swift-org-page"`.
        /// Default implementation returns nil so the helper falls
        /// back to its own default tag.
        func availabilitySource(for url: URL) -> String?
    }

    /// Companion tuple type for `PlatformVersionsResolver.versions`.
    /// Matches the 5 platform-version fields the indexer accepts.
    public struct PlatformVersions: Sendable, Equatable {
        public let iOS: String?
        public let macOS: String?
        public let tvOS: String?
        public let watchOS: String?
        public let visionOS: String?

        public init(iOS: String?, macOS: String?, tvOS: String?, watchOS: String?, visionOS: String?) {
            self.iOS = iOS
            self.macOS = macOS
            self.tvOS = tvOS
            self.watchOS = watchOS
            self.visionOS = visionOS
        }

        /// Pre-#1095 baseline: every swift-org/swift-book row got
        /// stamped with these values (Swift's first-shipping version
        /// per platform). Strategies that don't supply a resolver
        /// inherit this.
        public static let universalSwift = PlatformVersions(
            iOS: "8.0", macOS: "10.9", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"
        )
    }
}

// #1103: default implementation lives at file scope because Swift
// does not permit nesting an `extension Search.PlatformVersionsResolver`
// block inside an `extension Search` block. The fully-qualified name
// reaches the same protocol either way; the choice is purely about
// syntactic placement.
public extension Search.PlatformVersionsResolver {
    func implementationSwiftVersion(for _: URL) -> String? {
        nil
    }

    func availabilitySource(for _: URL) -> String? {
        nil
    }
}
