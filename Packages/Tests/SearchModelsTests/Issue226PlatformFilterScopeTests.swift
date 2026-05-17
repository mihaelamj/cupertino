import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #226 — Search.PlatformFilterScope

// This file pins the source-of-truth bucket assignments + the notice-formatting
// helper. Both behaviours must remain stable across refactors:
//
//   1. The `appliesFilter` / `silentlyIgnoresFilter` partition decides
//      whether the cross-source partial-filter notice fires; getting it
//      wrong silently misleads AI clients about which results were
//      filtered.
//   2. The `partialNoticeMarkdown` output must carry the stable
//      `platform_filter_partial` marker so AI clients can grep for it
//      rather than parsing prose.

@Suite("#226 — Search.PlatformFilterScope bucket assignments")
struct Issue226PlatformFilterScopeBucketsTests {
    @Test("dispatchAppliesFilter covers the 6 handleSearchDocs-routed sources")
    func dispatchAppliesFilterMembership() {
        // All 6 sources route through `CompositeToolProvider.handleSearchDocs`
        // which threads the 5 `min_*` args + minSwift into `Search.Database.search`.
        // The handler applies the filter uniformly; row-level results
        // depend on whether the source's data has populated `min_*` columns
        // (sparse data manifests as fewer results, not as unfiltered ones).
        #expect(Search.PlatformFilterScope.dispatchAppliesFilter == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.packages,
        ])
    }

    @Test("dispatchDropsFilter covers hig + the samples aliases")
    func dispatchDropsFilterMembership() {
        // Post-#226 expansion, `handleSearchSamples` now applies the
        // filter via the single-platform precedence pick. The samples /
        // apple-sample-code source remains in this bucket for the
        // fan-out case (#732 follow-up — the fan-out's
        // `unifiedService.searchSamples` path still uses
        // `Sample.Index.Database.searchProjects` which doesn't accept
        // platform args). When #732 lands and `searchProjects` gains
        // the args, samples + apple-sample-code can move to
        // `dispatchAppliesFilter`. HIG is structurally unfilterable
        // (no platform-version axis on the data).
        #expect(Search.PlatformFilterScope.dispatchDropsFilter == [
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleSampleCode,
        ])
    }

    @Test("dispatchAppliesFilter and dispatchDropsFilter are disjoint")
    func bucketsDisjoint() {
        let overlap = Search.PlatformFilterScope.dispatchAppliesFilter
            .intersection(Search.PlatformFilterScope.dispatchDropsFilter)
        #expect(overlap.isEmpty, "A source cannot be in both buckets")
    }

    @Test("allFanOutSources is the unified-tool fan-out list (no aliases)")
    func fanOutMembership() {
        // appleSampleCode is canonicalised to samples by the dispatcher,
        // so it must NOT appear in the fan-out enumeration (would
        // double-count the samples source).
        #expect(Search.PlatformFilterScope.allFanOutSources.contains(
            Shared.Constants.SourcePrefix.samples
        ))
        #expect(!Search.PlatformFilterScope.allFanOutSources.contains(
            Shared.Constants.SourcePrefix.appleSampleCode
        ))
        #expect(Search.PlatformFilterScope.allFanOutSources.count == 8)
    }
}

@Suite("#226 — Search.PlatformFilterScope.partitionForNotice")
struct Issue226PartitionForNoticeTests {
    @Test("Mixed-source contributing list partitions correctly")
    func mixedSourcesPartition() {
        // Post-#226 expansion: swift-evolution / swift-org / swift-book /
        // apple-archive now route through `handleSearchDocs` which DOES
        // apply the filter. Only `hig` + samples are unfiltered at the
        // tool-handler boundary today.
        let result = Search.PlatformFilterScope.partitionForNotice(contributingSources: [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.packages,
            Shared.Constants.SourcePrefix.swiftEvolution,
        ])
        #expect(result.filtered == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.packages,
            Shared.Constants.SourcePrefix.swiftEvolution,
        ])
        #expect(result.unfiltered == [
            Shared.Constants.SourcePrefix.hig,
        ])
    }

    @Test("All-aware contributing list partitions with empty unfiltered")
    func allAware() {
        let result = Search.PlatformFilterScope.partitionForNotice(contributingSources: [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.packages,
        ])
        #expect(result.unfiltered.isEmpty)
        #expect(result.filtered.count == 2)
    }

    @Test("Only hig + samples remain unaware post-#226 expansion")
    func onlyHigAndSamplesUnaware() {
        // Sanity-check the post-expansion bucket shape: hig + samples
        // (+ apple-sample-code alias) are the only sources that stay in
        // `dispatchDropsFilter`. Swift-evolution / swift-org / swift-book /
        // apple-archive all moved to `dispatchAppliesFilter` because
        // their dispatch goes through `handleSearchDocs` which now
        // threads platform args at the SQL boundary.
        let result = Search.PlatformFilterScope.partitionForNotice(contributingSources: [
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.samples,
        ])
        #expect(result.filtered.isEmpty)
        #expect(result.unfiltered.count == 2)
    }

    @Test("Unknown source is conservatively partitioned as unfiltered")
    func unknownSourceConservative() {
        // If a future source ID slips through unregistered, the notice
        // fires rather than silently claiming filtration. Healthy bias
        // toward over-reporting vs misleading AI clients.
        let result = Search.PlatformFilterScope.partitionForNotice(contributingSources: ["mystery-source"])
        #expect(result.filtered.isEmpty)
        #expect(result.unfiltered == ["mystery-source"])
    }

    @Test("Empty input returns empty partition")
    func emptyInput() {
        let result = Search.PlatformFilterScope.partitionForNotice(contributingSources: [])
        #expect(result.filtered.isEmpty)
        #expect(result.unfiltered.isEmpty)
    }
}

@Suite("#226 — Search.PlatformFilterScope.dispatchSources")
struct Issue226DispatchSourcesTests {
    @Test(
        "nil / empty / 'all' all resolve to the fan-out source list",
        arguments: [nil, "", "all"] as [String?]
    )
    func nilOrAllFansOut(input: String?) {
        let result = Search.PlatformFilterScope.dispatchSources(for: input)
        #expect(result == Search.PlatformFilterScope.allFanOutSources)
    }

    @Test("Specific known source resolves to itself")
    func specificSourceResolvesToSelf() {
        #expect(Search.PlatformFilterScope.dispatchSources(for: Shared.Constants.SourcePrefix.appleDocs)
            == [Shared.Constants.SourcePrefix.appleDocs])
        #expect(Search.PlatformFilterScope.dispatchSources(for: Shared.Constants.SourcePrefix.hig)
            == [Shared.Constants.SourcePrefix.hig])
    }

    @Test("apple-sample-code alias canonicalises to samples")
    func appleSampleCodeCanonicalises() {
        let result = Search.PlatformFilterScope.dispatchSources(
            for: Shared.Constants.SourcePrefix.appleSampleCode
        )
        #expect(result == [Shared.Constants.SourcePrefix.samples])
    }

    @Test("Unknown source resolves to itself (tool throws later; partition treats it as unfiltered)")
    func unknownSourceResolvesToSelf() {
        // Post-#226 critic-pass: unknown sources resolve to `[source]`
        // rather than `[]` so the notice partitioning treats them as
        // unfiltered (the conservative classification). The tool-level
        // dispatch still throws for unknown sources before any search
        // runs, but the notice decision is made pre-dispatch so this
        // path still has to return something honest.
        let result = Search.PlatformFilterScope.dispatchSources(for: "no-such-source")
        #expect(result == ["no-such-source"])
    }
}

@Suite("#226 — Search.PlatformFilterScope.partialNoticeMarkdown")
struct Issue226PartialNoticeMarkdownTests {
    @Test("Empty platform descriptions returns nil (no filter intended)")
    func noPlatformDescriptionsReturnsNil() {
        let result = Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: [],
            dispatch: .singleSource(Shared.Constants.SourcePrefix.hig),
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        )
        #expect(result == nil)
    }

    @Test("Single-source dispatch through aware source returns nil")
    func singleSourceAwareReturnsNil() {
        let result = Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            dispatch: .singleSource(Shared.Constants.SourcePrefix.appleDocs),
            contributingSources: [Shared.Constants.SourcePrefix.appleDocs]
        )
        #expect(result == nil, "apple-docs goes through handleSearchDocs which applies the filter")
    }

    @Test("Single-source dispatch through unaware source fires")
    func singleSourceUnawareFires() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            dispatch: .singleSource(Shared.Constants.SourcePrefix.hig),
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        ))
        #expect(result.contains("platform_filter_partial"))
        #expect(result.contains("min_ios=18.0"))
        #expect(result.contains(Shared.Constants.SourcePrefix.hig))
    }

    @Test("Fan-out dispatch reports ALL contributing sources as unfiltered when handleSearchAll drops them")
    func fanOutReportsAllUnfiltered() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            dispatch: .fanOut,
            contributingSources: [
                Shared.Constants.SourcePrefix.appleDocs,
                Shared.Constants.SourcePrefix.hig,
                Shared.Constants.SourcePrefix.samples,
            ]
        ))
        // Post-#226 expansion: handleSearchAll DOES thread platform args
        // through to searchSource for 6 of 7 sources. Samples in the
        // fan-out remains unfiltered today (#732). But the notice
        // helper's `.fanOut` case reports all contributing sources as
        // unfiltered conservatively — the wiring in `handleSearch`
        // decides which dispatch kind to use; this case is the "old
        // semantics" guard for callers that pass `.fanOut` to indicate
        // every source is at-risk.
        #expect(result.contains("platform_filter_partial"))
    }

    @Test("Multiple platform descriptions are all listed")
    func multiplePlatforms() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0", "min_macos=14.0"],
            dispatch: .singleSource(Shared.Constants.SourcePrefix.hig),
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        ))
        #expect(result.contains("min_ios=18.0"))
        #expect(result.contains("min_macos=14.0"))
    }

    @Test("Output is a markdown blockquote (starts with '> ')")
    func outputIsBlockquote() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            dispatch: .singleSource(Shared.Constants.SourcePrefix.hig),
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        ))
        #expect(result.hasPrefix("> "))
    }

    @Test("Output ends with blank-line separator (clean prepend)")
    func outputEndsWithBlankLine() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            dispatch: .singleSource(Shared.Constants.SourcePrefix.hig),
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        ))
        // Trailing "\n\n" so prepending to existing markdown produces a
        // clean separation between the notice and the search results body.
        #expect(result.hasSuffix("\n\n"))
    }
}
