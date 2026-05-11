import Foundation
@testable import Search
import Testing

// Truth-table coverage for `Search.IndexBuilder.titleLooksLikeHTTPErrorTemplate`,
// the indexer-side defense added as a belt-and-suspenders to PR #289's
// crawler-side gate. Even if a poison JSON file lands on disk via mid-flight
// rsync, restored backup, or hand-edited corpus, the indexer must refuse to
// index it.
//
// The audit on the v1.0.2 bundle saw 23 × "403 Forbidden" + 45 × "502 Bad
// Gateway" rows; this defense would have caught all of them at index time.

@Suite("Search.IndexBuilder.titleLooksLikeHTTPErrorTemplate (#284 indexer defense)")
struct IndexBuilderTitleErrorDefenseTests {
    typealias SUT = Search.IndexBuilder

    // MARK: status-prefix form

    @Test(
        "every spec'd status-prefix title trips the gate",
        arguments: [
            "403 Forbidden",
            "404 Not Found",
            "429 Too Many Requests",
            "500 Internal Server Error",
            "502 Bad Gateway",
            "503 Service Unavailable",
            "504 Gateway Timeout",
        ]
    )
    func statusPrefixTitlesAreDetected(title: String) {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate(title) == true)
    }

    @Test("status-prefix at end-of-string also trips (no trailing phrase)")
    func bareStatusCodeIsDetected() {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("502") == true)
    }

    // MARK: standalone phrase form

    @Test(
        "standalone error phrases trip the gate",
        arguments: [
            "Forbidden",
            "Bad Gateway",
            "Not Found",
            "Service Unavailable",
            "Gateway Timeout",
            "Too Many Requests",
            "Internal Server Error",
        ]
    )
    func standalonePhrasesAreDetected(title: String) {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate(title) == true)
    }

    @Test("standalone with whitespace trims correctly")
    func whitespaceTrimming() {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("  Bad Gateway  ") == true)
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("\n502 Bad Gateway\n") == true)
    }

    // MARK: real Apple titles MUST NOT trip

    @Test(
        "real Apple symbol titles must NOT be flagged",
        arguments: [
            "AVCustomMediaSelectionScheme",
            "withTaskGroup(of:returning:isolation:body:)",
            "UIDropOperation.forbidden", // contains "forbidden" but not standalone
            "MTRAccessControlAccessRestrictionType.attributeAccessForbidden",
            "AVError.Code.referenceForbiddenByReferencePolicy",
            "Routing404Type", // contains digits but not status prefix
            "callAsyncJavaScript(_:arguments:in:contentWorld:)",
            "GameCenterLeaderboardSetLocalization.Attributes",
            "Handling Bad Gateway responses in Apps and Books API", // legit doc that mentions phrase mid-sentence
            "Interpreting error codes (400, 401, 403)", // legit doc page about error codes
        ]
    )
    func realAppleTitlesAreNotFlagged(title: String) {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate(title) == false)
    }

    // MARK: degenerate inputs

    @Test("empty title returns false (handled by the existing missing-title guard)")
    func emptyTitleReturnsFalse() {
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("") == false)
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("   ") == false)
    }

    @Test("status code without proper boundary is not flagged (e.g. '502abc')")
    func bareDigitsWithoutBoundaryAreNotFlagged() {
        // The regex requires a whitespace or end-of-string anchor after the
        // status code. "502abc" lacks that, so it's not flagged. Pinned so a
        // future loosening of the regex is a conscious decision.
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("502abc") == false)
        #expect(SUT.titleLooksLikeHTTPErrorTemplate("404Type") == false)
    }
}
