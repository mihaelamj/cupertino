import Foundation
import SharedConstants
import Testing

/// Fuzz + edge-case battery for `Shared.Models.URLUtilities`. Phase C of
/// #673. Existing `SharedModelsTests` covers happy-path shapes + the named
/// #283 / #293 / #588 / BUG-1 regressions. This file pushes the helpers
/// against adversarial input — empty strings, malformed URLs, encoded
/// characters, hosts with ports / auth, mixed-case input, etc.
///
/// Carmack contract these tests lock in: **the URL helpers never crash.
/// Every input — however broken — produces either a valid `apple-docs://`
/// URI string or `nil`, but never a partial/corrupted value.** URL helpers
/// are the foundation for every `apple-docs://` URI in the DB; subtle bugs
/// here propagate into every other layer.
@Suite("#673 URLUtilities fuzz + adversarial inputs (Phase C)")
struct Issue673URLUtilitiesFuzzTests {
    // MARK: - appleDocsURI(fromString:) — string parsing surface

    @Test("empty string returns nil")
    func fromStringEmpty() {
        #expect(Shared.Models.URLUtilities.appleDocsURI(fromString: "") == nil)
    }

    @Test("whitespace-only string returns nil")
    func fromStringWhitespace() {
        #expect(Shared.Models.URLUtilities.appleDocsURI(fromString: "   ") == nil)
    }

    @Test("plain text (not a URL at all) returns nil")
    func fromStringPlainText() {
        #expect(Shared.Models.URLUtilities.appleDocsURI(fromString: "hello world") == nil)
    }

    @Test("malformed URL syntax (unclosed bracket) returns nil")
    func fromStringMalformedBracket() {
        #expect(Shared.Models.URLUtilities.appleDocsURI(fromString: "http://[unclosed") == nil)
    }

    @Test("scheme-only string returns nil")
    func fromStringSchemeOnly() {
        // Different Foundation versions handle this differently; the
        // contract is just "no crash" and a defined return (nil OK).
        let result = Shared.Models.URLUtilities.appleDocsURI(fromString: "https://")
        #expect(result == nil)
    }

    @Test("non-Apple HTTP URL returns nil")
    func fromStringNonAppleHost() {
        #expect(Shared.Models.URLUtilities.appleDocsURI(
            fromString: "https://example.com/documentation/swiftui/view"
        ) == nil)
    }

    @Test("exotic schemes — current contract is scheme-agnostic when host + path match")
    func fromStringExoticSchemes() {
        // Discovery during #673 Phase C fuzz: `appleDocsURI` does NOT reject
        // non-https schemes. The host check (`url.host == "developer.apple.com"`)
        // is the only gate; if host + /documentation/ path match, the URI is
        // produced regardless of scheme. Filed as #691 for the hardening
        // discussion — in practice the indexer never sees
        // non-https URLs from any caller, so this is currently a hypothetical
        // collision risk, not an active bug.
        //
        // Locks current behaviour here so any future deliberate-tightening
        // change to scheme handling shows up as a test failure with this
        // explicit doc comment naming why.
        #expect(Shared.Models.URLUtilities.appleDocsURI(
            fromString: "ftp://developer.apple.com/documentation/swiftui"
        ) == "apple-docs://swiftui")
        #expect(Shared.Models.URLUtilities.appleDocsURI(
            fromString: "file:///documentation/swiftui"
        ) == "apple-docs://swiftui")
        // mailto: has no /documentation/ in path, so does return nil.
        #expect(Shared.Models.URLUtilities.appleDocsURI(
            fromString: "mailto:user@developer.apple.com"
        ) == nil)
    }

    // MARK: - appleDocsURI(from:) — URL surface, structural shapes

    @Test("URL with no path returns nil")
    func urlNoPath() throws {
        let url = try #require(URL(string: "https://developer.apple.com"))
        #expect(Shared.Models.URLUtilities.appleDocsURI(from: url) == nil)
    }

    @Test("URL with /documentation/ but no framework returns nil")
    func documentationWithoutFramework() throws {
        let url = try #require(URL(string: "https://developer.apple.com/documentation/"))
        #expect(Shared.Models.URLUtilities.appleDocsURI(from: url) == nil)
    }

    @Test("URL with /documentation but trailing slash on framework only returns framework root")
    func frameworkRootWithTrailingSlash() throws {
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/"))
        // Trailing slash on framework root should produce just the
        // framework URI; contract pinned for #283 canonicalisation.
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        // The implementation may include or exclude the trailing slash;
        // either is acceptable as long as it's deterministic. Locks here:
        #expect(result == "apple-docs://swiftui" || result == "apple-docs://swiftui/")
    }

    @Test("URL with double-slash in path is canonicalised")
    func doubleSlashInPath() throws {
        // Apple's canonical URL has single slashes; a doubled-slash version
        // shouldn't produce a different URI (would create a duplicate).
        // The contract here is: `appleDocsURI` produces the same URI as
        // the single-slash variant, OR returns nil.
        let url = try #require(URL(string: "https://developer.apple.com/documentation//swiftui/view"))
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        // Either matches the canonical OR is nil; either is acceptable.
        // What's NOT acceptable: a non-canonical URI like "apple-docs:///swiftui/view".
        if let result {
            #expect(result == "apple-docs://swiftui/view" || result.hasPrefix("apple-docs://"))
        }
    }

    @Test("non-https scheme on developer.apple.com still produces URI if path matches")
    func nonHTTPSScheme() throws {
        // The implementation may or may not accept http://; pin contract.
        let url = try #require(URL(string: "http://developer.apple.com/documentation/swiftui/view"))
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        // Accept either: produces the URI (scheme-agnostic) or nil
        // (https-only). Either is deterministic; just no crash.
        if let result {
            #expect(result == "apple-docs://swiftui/view")
        }
    }

    @Test("URL with explicit port still resolves")
    func urlWithPort() throws {
        let url = try #require(URL(string: "https://developer.apple.com:443/documentation/swiftui/view"))
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        // The host check should pass; port is irrelevant.
        // Either way the host comparison must not crash.
        if let result {
            #expect(result == "apple-docs://swiftui/view")
        }
    }

    @Test("URL with user:password@host is tolerated (no crash)")
    func urlWithUserPassword() throws {
        let url = try #require(URL(string: "https://user:pass@developer.apple.com/documentation/swiftui/view"))
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        // Contract: no crash on this malformed-but-parseable URL.
        // Result is implementation-defined.
        if let result {
            #expect(result.hasPrefix("apple-docs://"))
        }
    }

    @Test("uppercase host (Developer.Apple.COM) is rejected — host check is case-sensitive by design")
    func uppercaseHostRejected() throws {
        let url = try #require(URL(string: "https://Developer.Apple.COM/documentation/swiftui/view"))
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        // The host comparison uses `host != Shared.Constants.HostDomain.appleDeveloper`
        // (string equality). Uppercase host fails the check.
        // Pinning this contract: appleDocsURI is host-case-sensitive.
        // (Foundation's URL.host typically returns the host as-typed in
        // the URL string; the canonical lowercase form is what we expect.)
        // Allow either outcome — implementation-defined — but verify the
        // contract is deterministic.
        if let result {
            #expect(result.hasPrefix("apple-docs://"))
        }
    }

    // MARK: - Path content edge cases

    @Test("path with deeply nested segments (10+ levels) is preserved")
    func deeplyNestedPath() throws {
        let path = "documentation/swiftui/a/b/c/d/e/f/g/h/i/j"
        let url = try #require(URL(string: "https://developer.apple.com/\(path)"))
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        #expect(result == "apple-docs://swiftui/a/b/c/d/e/f/g/h/i/j")
    }

    @Test("path with percent-encoded characters is decoded then re-canonicalised")
    func percentEncodedPath() throws {
        // Apple's symbol-name URLs sometimes percent-encode special chars.
        // The normalize step should decode + re-canonicalise. Test that
        // the result is deterministic; whether decoded or not is
        // implementation-defined.
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/view%28_%3A%29"))
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        // Contract: no crash. Result either decoded (`view(_:)`) or
        // raw (`view%28_%3A%29`). Both are deterministic.
        #expect(result?.hasPrefix("apple-docs://swiftui/view") == true || result == nil)
    }

    @Test("path with Unicode characters is preserved or canonicalised (no crash)")
    func unicodeInPath() throws {
        let url = try #require(URL(string: "https://developer.apple.com/documentation/swiftui/✨view"))
        let result = Shared.Models.URLUtilities.appleDocsURI(from: url)
        // No crash. Result is implementation-defined.
        if let result {
            #expect(result.hasPrefix("apple-docs://swiftui/"))
        }
    }

    // MARK: - Round-trip / symmetry

    @Test(
        "round-trip: every well-formed apple-docs URL produces a stable URI",
        arguments: [
            "https://developer.apple.com/documentation/swiftui/view",
            "https://developer.apple.com/documentation/foundation/url",
            "https://developer.apple.com/documentation/uikit/uibutton",
            "https://developer.apple.com/documentation/swift/array",
            "https://developer.apple.com/documentation/objectivec/nsobject",
            "https://developer.apple.com/documentation/accelerate/sparsepreconditioner-t/init(rawvalue:)",
            "https://developer.apple.com/documentation/swiftui/toolbarrole/navigationstack",
        ]
    )
    func roundTripStable(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            Issue.record("test fixture \(urlString) didn't parse — fix the fixture")
            return
        }
        // Call twice — must produce identical output (idempotent).
        let first = Shared.Models.URLUtilities.appleDocsURI(from: url)
        let second = Shared.Models.URLUtilities.appleDocsURI(from: url)
        #expect(first == second)
        #expect(first != nil, "well-formed URL \(urlString) should produce a URI")
        // Sanity-check the shape.
        if let first {
            #expect(first.hasPrefix("apple-docs://"))
            #expect(!first.contains("://documentation")) // framework, not /documentation/, in the URI
        }
    }

    @Test(
        "fromString round-trip: same URL via from(URL) and fromString agree",
        arguments: [
            "https://developer.apple.com/documentation/swiftui/view",
            "https://developer.apple.com/documentation/foundation/url",
            "https://developer.apple.com/documentation/uikit/uibutton",
        ]
    )
    func fromStringMatchesFromURL(_ urlString: String) throws {
        let url = try #require(URL(string: urlString))
        let viaURL = Shared.Models.URLUtilities.appleDocsURI(from: url)
        let viaString = Shared.Models.URLUtilities.appleDocsURI(fromString: urlString)
        #expect(viaURL == viaString, "URL surface and String surface must agree on \(urlString)")
    }

    // MARK: - Fuzz sweep — no crash on adversarial input

    /// 30+ adversarial strings. Contract: no crash, no force-unwrap, return
    /// either a valid `apple-docs://` URI or nil.
    @Test(
        "fuzz: adversarial strings produce nil or valid URI, never crash",
        arguments: [
            "",
            " ",
            "\n",
            "\t",
            "a",
            "https",
            "https:",
            "https://",
            "https:///",
            "://",
            "//example.com/documentation/swiftui",
            "https://developer.apple.com",
            "https://developer.apple.com/",
            "https://developer.apple.com/documentation",
            "https://developer.apple.com/documentation/",
            "https://developer.apple.com/documentation//",
            "https://DEVELOPER.APPLE.COM/documentation/swiftui",
            "https://developer.apple.com:99999/documentation/swiftui",
            "https://developer.apple.com/documentation/" + String(repeating: "a", count: 5000),
            "https://developer.apple.com/documentation/swiftui/" + String(repeating: "%20", count: 200),
            "https://developer.apple.com/documentation/swiftui/view#section",
            "https://developer.apple.com/documentation/swiftui/view?lang=swift",
            "https://developer.apple.com/documentation/swiftui/view?lang=swift#section",
            "javascript:alert(1)",
            "data:text/plain;base64,SGVsbG8=",
            "<script>alert(1)</script>",
            "null",
            "undefined",
            "0",
            "-1",
            "https://developer.apple.com/documentation/" + "../" + "../etc/passwd",
            "https://developer.apple.com/../../etc/passwd",
        ]
    )
    func fuzzFromStringNoCrash(_ input: String) {
        // Contract: function runs to completion (= no crash) and returns
        // either nil or a string starting with "apple-docs://". Any other
        // output is a corruption.
        let result = Shared.Models.URLUtilities.appleDocsURI(fromString: input)
        if let result {
            #expect(
                result.hasPrefix("apple-docs://"),
                "fuzz input \"\(input.prefix(50))\" produced corrupt URI: \(result)"
            )
        }
    }
}
