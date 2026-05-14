import Foundation
import SharedConstants
import SharedUtils
import Testing

// Direct coverage for the `URL(knownGood:)` throwing initializer introduced in
// the v1.0.2-followup refactor (PR #288), replacing the fatalError-based
// `URL.knownGood(_:file:line:)` static method (issue #318).

@Suite("URL(knownGood:)")
struct URLKnownGoodTests {
    @Test("returns the URL for a literal https string")
    func returnsURLForLiteralString() throws {
        let url = try URL(knownGood: "https://developer.apple.com/documentation/swiftui")
        #expect(url.absoluteString == "https://developer.apple.com/documentation/swiftui")
        #expect(url.scheme == "https")
        #expect(url.host == "developer.apple.com")
        #expect(url.path == "/documentation/swiftui")
    }

    @Test("returns the URL for a string interpolated from internal constants")
    func returnsURLForInterpolatedString() throws {
        let owner = "apple"
        let repo = "swift-syntax"
        let url = try URL(knownGood: "\(Shared.Constants.BaseURL.githubAPIRepos)/\(owner)/\(repo)")
        #expect(url.absoluteString == "https://api.github.com/repos/apple/swift-syntax")
    }

    @Test("preserves a query string component intact")
    func preservesQueryString() throws {
        let url = try URL(knownGood: "https://api.github.com/repos/x/y/contents/z?ref=main")
        #expect(url.query == "ref=main")
        #expect(url.path == "/repos/x/y/contents/z")
    }

    @Test("throws URLError(.badURL) for a malformed string")
    func throwsForMalformedString() {
        // Malformed IPv6 literal — Foundation's URL(string:) returns nil.
        #expect(throws: URLError.self) {
            try URL(knownGood: "http://[bad ipv6")
        }
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
            let viaHelper = try URL(knownGood: candidate)
            let viaInit = try #require(URL(string: candidate))
            #expect(viaHelper == viaInit)
        }
    }
}
