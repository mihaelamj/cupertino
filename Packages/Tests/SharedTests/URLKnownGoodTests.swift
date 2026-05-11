import Foundation
import Shared
import Testing

// Direct coverage for the `URL.knownGood(_:file:line:)` helper introduced in
// the v1.0.2-followup refactor (PR #288). The fatal-error branch on
// malformed input cannot be exercised from a unit test without crashing
// the host process; these tests cover the happy paths it's actually used
// for in production.

@Suite("URL.knownGood")
struct URLKnownGoodTests {
    @Test("returns the URL for a literal https string")
    func returnsURLForLiteralString() {
        let url = URL.knownGood("https://developer.apple.com/documentation/swiftui")
        #expect(url.absoluteString == "https://developer.apple.com/documentation/swiftui")
        #expect(url.scheme == "https")
        #expect(url.host == "developer.apple.com")
        #expect(url.path == "/documentation/swiftui")
    }

    @Test("returns the URL for a string interpolated from internal constants")
    func returnsURLForInterpolatedString() {
        let owner = "apple"
        let repo = "swift-syntax"
        let url = URL.knownGood("\(Shared.Constants.BaseURL.githubAPIRepos)/\(owner)/\(repo)")
        #expect(url.absoluteString == "https://api.github.com/repos/apple/swift-syntax")
    }

    @Test("preserves a query string component intact")
    func preservesQueryString() {
        let url = URL.knownGood("https://api.github.com/repos/x/y/contents/z?ref=main")
        #expect(url.query == "ref=main")
        #expect(url.path == "/repos/x/y/contents/z")
    }

    @Test("matches plain URL(string:) on every BaseURL constant we ship")
    func matchesPlainInitForBaseURLConstants() throws {
        // Sanity sweep: every Shared.Constants.BaseURL string we depend on
        // at call sites must produce the same URL through both paths.
        let candidates: [String] = [
            Shared.Constants.BaseURL.appleDeveloper,
            Shared.Constants.BaseURL.appleDeveloperDocs,
            Shared.Constants.BaseURL.appleHIG,
            Shared.Constants.BaseURL.appleSampleCode,
            Shared.Constants.BaseURL.appleDeveloperAccount,
            Shared.Constants.BaseURL.swiftPackageList,
            Shared.Constants.BaseURL.githubAPIRepos,
        ]

        for candidate in candidates {
            let viaHelper = URL.knownGood(candidate)
            let viaInit = try #require(URL(string: candidate))
            #expect(viaHelper == viaInit)
        }
    }
}
