import Foundation
import SearchModels
@testable import SwiftBookSource
@testable import SwiftOrgSource
import Testing

/// #1116: `availability_source` is now per-resolver, not hardcoded
/// to `"swift-book-chapter"` for every page that flows through the
/// crawl helper's per-page-resolver branch. Pre-fix every swift-org
/// row was mislabelled with `swift-book-chapter` because the helper
/// applied one static string whenever a resolver was supplied.
@Suite("#1116 availability_source per-resolver tagging")
struct Issue1116AvailabilitySourceResolverTagTests {
    @Test("SwiftBookChapterVersionsResolver returns swift-book-chapter")
    func swiftBookResolverTag() throws {
        let resolver = SwiftBookChapterVersionsResolver()
        let url = try #require(URL(string: "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency"))
        #expect(resolver.availabilitySource(for: url) == "swift-book-chapter")
    }

    @Test("SwiftOrgPlatformResolver: cross-platform page tags swift-org-universal")
    func swiftOrgUniversalTag() throws {
        let resolver = SwiftOrgPlatformResolver()
        let url = try #require(URL(string: "https://www.swift.org/blog/swift-6-1-released/"))
        #expect(resolver.availabilitySource(for: url) == "swift-org-universal")
    }

    @Test("SwiftOrgPlatformResolver: server-side page tags swift-org-linux-server")
    func swiftOrgLinuxServerTag() throws {
        let resolver = SwiftOrgPlatformResolver()
        let serverPath = try #require(URL(string: "https://www.swift.org/documentation/server/getting-started-with-aws/"))
        #expect(resolver.availabilitySource(for: serverPath) == "swift-org-linux-server")

        let serverSlug = try #require(URL(string: "https://www.swift.org/documentation_server_aws-lambda"))
        #expect(resolver.availabilitySource(for: serverSlug) == "swift-org-linux-server")
    }

    @Test("Default PlatformVersionsResolver extension returns nil for the new tag too")
    func defaultExtensionAvailabilitySource() throws {
        let resolver = NoOpResolver()
        let url = try #require(URL(string: "https://example.com/anything"))
        #expect(resolver.availabilitySource(for: url) == nil)
    }
}

/// Minimal resolver that only implements `versions(for:)`; the
/// default extensions for `implementationSwiftVersion(for:)` and
/// `availabilitySource(for:)` must both kick in.
private struct NoOpResolver: Search.PlatformVersionsResolver {
    func versions(for _: URL) -> Search.PlatformVersions {
        .universalSwift
    }
}
