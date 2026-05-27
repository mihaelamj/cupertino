import Foundation
import SearchModels
import SwiftBookSource
import Testing

/// #1103: each `SwiftBookChapterVersions.ChapterFloor` carries the
/// Swift toolchain version that gates the chapter's content
/// (concurrency → 5.5, macros → 5.9; baseline → nil). The
/// `PlatformVersionsResolver.implementationSwiftVersion(for:)` default
/// extension returns nil; swift-book's resolver overrides to surface
/// the chapter version.
@Suite("#1103 swift-book chapter Swift-version stamping")
struct Issue1103SwiftBookChapterSwiftVersionTests {
    @Test("Concurrency chapter floor carries swiftVersion = 5.5")
    func concurrencySwiftVersion() {
        let floor = SwiftBookChapterVersions.floor(forSlug: "concurrency")
        #expect(floor.swiftVersion == "5.5")
        #expect(floor.iOS == "13.0")
    }

    @Test("StructuredConcurrency + Actors chapters share the 5.5 floor")
    func structuredConcurrencyAndActorsSwiftVersion() {
        #expect(SwiftBookChapterVersions.floor(forSlug: "structuredconcurrency").swiftVersion == "5.5")
        #expect(SwiftBookChapterVersions.floor(forSlug: "actors").swiftVersion == "5.5")
    }

    @Test("Macros chapter floor carries swiftVersion = 5.9")
    func macrosSwiftVersion() {
        let floor = SwiftBookChapterVersions.floor(forSlug: "macros")
        #expect(floor.swiftVersion == "5.9")
        #expect(floor.iOS == "17.0")
    }

    @Test("Universal baseline chapter has swiftVersion = nil (no useful tag)")
    func universalBaselineSwiftVersion() {
        let baseline = SwiftBookChapterVersions.floor(forSlug: "thebasics")
        #expect(baseline.swiftVersion == nil)
        #expect(baseline == SwiftBookChapterVersions.ChapterFloor.universalSwiftBaseline)
    }

    @Test("Default PlatformVersionsResolver extension returns nil for non-overriders")
    func defaultResolverReturnsNil() throws {
        let resolver = NoOpResolver()
        let url = try #require(URL(string: "https://example.com/whatever"))
        #expect(resolver.implementationSwiftVersion(for: url) == nil)
    }
}

/// Minimal resolver that only implements `versions(for:)`; the
/// `implementationSwiftVersion(for:)` default extension must apply.
private struct NoOpResolver: Search.PlatformVersionsResolver {
    func versions(for _: URL) -> Search.PlatformVersions {
        .universalSwift
    }
}
