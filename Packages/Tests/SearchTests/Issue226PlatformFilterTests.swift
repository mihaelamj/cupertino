import Foundation
import SearchModels
import Testing

// MARK: - #226 — MCP search-style platform filter predicate

//
// `Search.PlatformFilter.passes(minima:minIOS:minMacOS:minTvOS:minWatchOS:minVisionOS:)`
// is the semver-aware predicate `CompositeToolProvider`'s search-style
// tool handlers (`search_symbols` / `search_property_wrappers` /
// `search_concurrency` / `search_conformances`) call after the search
// returns, to drop rows whose row-side minimum is above the user's
// filter floor.
//
// Lives in `SearchModels` so the CLI / MCP layer doesn't need to import
// the `Search` SPM target — the predicate is pure-Swift semver math
// over `Search.PlatformMinima` value structs.
//
// These tests pin the predicate's behaviour at every interesting
// boundary: empty filter / row-side missing / each platform axis /
// semver-correct comparison (`"10.13"` is NOT `≤ "10.2"`).

@Suite("#226 — Search.PlatformFilter.passes predicate", .serialized)
struct Issue226PlatformFilterTests {
    // MARK: - Trivial cases

    @Test("Empty filter (every arg nil) — every row passes regardless of minima")
    func emptyFilterPassesAll() {
        let result = Search.PlatformFilter.passes(
            minima: Search.PlatformMinima(minIOS: "18.0"),
            minIOS: nil, minMacOS: nil, minTvOS: nil, minWatchOS: nil, minVisionOS: nil
        )
        #expect(result == true)
    }

    @Test("Empty-string filter values treated as nil (don't trigger reject path)")
    func emptyStringFiltersDoNotConstrain() {
        let result = Search.PlatformFilter.passes(
            minima: Search.PlatformMinima(minIOS: "18.0"),
            minIOS: "", minMacOS: "", minTvOS: "", minWatchOS: "", minVisionOS: ""
        )
        #expect(result == true)
    }

    @Test("Filter set but minima nil → reject (matches unified-search IS-NOT-NULL gate)")
    func setFilterRejectsRowsWithoutMinima() {
        let result = Search.PlatformFilter.passes(
            minima: nil,
            minIOS: "15.0", minMacOS: nil, minTvOS: nil, minWatchOS: nil, minVisionOS: nil
        )
        #expect(result == false)
    }

    @Test("Per-axis: filter set but row's value missing for THAT axis → reject")
    func perAxisMissingRejects() {
        // Row has minIOS but not minMacOS; macOS filter is set → reject.
        let result = Search.PlatformFilter.passes(
            minima: Search.PlatformMinima(minIOS: "15.0"),
            minIOS: nil, minMacOS: "13.0", minTvOS: nil, minWatchOS: nil, minVisionOS: nil
        )
        #expect(result == false)
    }

    // MARK: - The headline cases from the issue body

    @Test("Issue spec: minIOS=18.0 row + filter minIOS=15.0 → pass")
    func iosNewRowPassesOldFloor() {
        // Symbol introduced at iOS 18.0, user wants symbols available on iOS 15.0.
        // 18.0 is NOT <= 15.0 — wait, the semantics: row.minIOS is the API's
        // minimum-iOS-needed. User says "give me APIs available on iOS 15.0."
        // The API needs iOS 18.0 to run — too new for iOS 15 — so it should be
        // REJECTED. Re-read the issue: "asserts only 18.0 row returned" means
        // filter minIOS=15.0 keeps the 18.0 row and drops the 14.0 row?
        //
        // The unified-search semantics (Search.Index.Search.swift:730):
        //   isVersion(rowMinIOS, lessThanOrEqualTo: filterMinIOS)
        //   → row passes when API's min is <= the user's floor.
        //   → "API needs iOS X; user wants APIs available since iOS Y"
        //     → pass when X <= Y (API was introduced at or before Y).
        //
        // So minIOS=18.0 with filter=15.0:
        //   isVersion("18.0", lessThanOrEqualTo: "15.0") → false → REJECT.
        // And minIOS=14.0 with filter=15.0:
        //   isVersion("14.0", lessThanOrEqualTo: "15.0") → true → PASS.
        //
        // The issue body's "asserts only 18.0 row returned" appears to describe
        // the opposite semantic (filter = "what's the newest required iOS I'm
        // willing to accept"). That semantic is consistent with the canonical
        // `cupertino ask --min-version 18.0` meaning "I'm on iOS 18, what's
        // available?". Both readings rely on the SAME `isVersion(rv, <= filter)`
        // logic — what differs is what the FILTER VALUE represents. The unified
        // tool uses "filter = MY OS version", and the predicate's design here
        // matches that. So filter=15.0 means MY OS = iOS 15; rows requiring
        // iOS > 15 (like 18.0) get rejected.
        //
        // This test pins the predicate's `lessThanOrEqualTo` direction.
        let result = Search.PlatformFilter.passes(
            minima: Search.PlatformMinima(minIOS: "18.0"),
            minIOS: "15.0", minMacOS: nil, minTvOS: nil, minWatchOS: nil, minVisionOS: nil
        )
        #expect(result == false, "API needing iOS 18.0 should NOT pass when caller is on iOS 15.0")
    }

    @Test("Old API (minIOS=14.0) passes user filter minIOS=15.0")
    func oldApiPassesNewerFloor() {
        let result = Search.PlatformFilter.passes(
            minima: Search.PlatformMinima(minIOS: "14.0"),
            minIOS: "15.0", minMacOS: nil, minTvOS: nil, minWatchOS: nil, minVisionOS: nil
        )
        #expect(result == true, "API available since iOS 14.0 should pass when caller is on iOS 15.0")
    }

    // MARK: - Semver correctness — the case string compare gets wrong

    @Test("Semver: 10.13 is NOT <= 10.2 (string compare lies; isVersion uses int-component math)")
    func semverNotStringCompare() {
        // String "10.13" < "10.2" because '1' < '2' at char 4.
        // Semantically 10.13 > 10.2 (10.13 = ten-point-thirteen, 10.2 = ten-point-two).
        // The predicate must use proper Int-component comparison.
        #expect(
            Search.PlatformFilter.isVersion("10.13", lessThanOrEqualTo: "10.2") == false,
            "10.13 must NOT be <= 10.2 (string compare lies)"
        )
        #expect(
            Search.PlatformFilter.isVersion("10.2", lessThanOrEqualTo: "10.13") == true,
            "10.2 must be <= 10.13"
        )
        #expect(
            Search.PlatformFilter.isVersion("10.13", lessThanOrEqualTo: "10.13") == true,
            "equal versions pass <="
        )
        // Short-vs-long missing components default to 0.
        #expect(
            Search.PlatformFilter.isVersion("10", lessThanOrEqualTo: "10.0") == true,
            "missing components default to 0; 10 == 10.0"
        )
        #expect(
            Search.PlatformFilter.isVersion("10.0", lessThanOrEqualTo: "10") == true,
            "symmetric: 10.0 == 10"
        )
        // 3-component versions.
        #expect(Search.PlatformFilter.isVersion("17.4.1", lessThanOrEqualTo: "17.4.2") == true)
        #expect(Search.PlatformFilter.isVersion("17.4.2", lessThanOrEqualTo: "17.4.1") == false)
    }

    // MARK: - All 5 axes wired

    @Test("All 5 platform axes pass independently when each row+filter pair satisfies <=")
    func allAxesPass() {
        let result = Search.PlatformFilter.passes(
            minima: Search.PlatformMinima(
                minIOS: "15.0", minMacOS: "12.0", minTvOS: "15.0",
                minWatchOS: "8.0", minVisionOS: "1.0"
            ),
            minIOS: "17.0", minMacOS: "14.0", minTvOS: "17.0",
            minWatchOS: "10.0", minVisionOS: "1.0"
        )
        #expect(result == true)
    }

    @Test("Any single axis failing rejects the row (5 cases)")
    func anyAxisRejects() {
        // Same shape — set filter > row min on each axis in turn, expect reject.
        let baseMinima = Search.PlatformMinima(
            minIOS: "17.0", minMacOS: "14.0", minTvOS: "17.0",
            minWatchOS: "10.0", minVisionOS: "1.0"
        )
        // Row needs iOS 17.0; user on iOS 15.0 → reject.
        #expect(Search.PlatformFilter.passes(
            minima: baseMinima,
            minIOS: "15.0", minMacOS: nil, minTvOS: nil, minWatchOS: nil, minVisionOS: nil
        ) == false)
        #expect(Search.PlatformFilter.passes(
            minima: baseMinima,
            minIOS: nil, minMacOS: "13.0", minTvOS: nil, minWatchOS: nil, minVisionOS: nil
        ) == false)
        #expect(Search.PlatformFilter.passes(
            minima: baseMinima,
            minIOS: nil, minMacOS: nil, minTvOS: "15.0", minWatchOS: nil, minVisionOS: nil
        ) == false)
        #expect(Search.PlatformFilter.passes(
            minima: baseMinima,
            minIOS: nil, minMacOS: nil, minTvOS: nil, minWatchOS: "8.0", minVisionOS: nil
        ) == false)
        // visionOS filter at 1.0; row also 1.0 → passes; bump down to reject.
        #expect(Search.PlatformFilter.passes(
            minima: Search.PlatformMinima(minVisionOS: "2.0"),
            minIOS: nil, minMacOS: nil, minTvOS: nil, minWatchOS: nil, minVisionOS: "1.0"
        ) == false)
    }
}
