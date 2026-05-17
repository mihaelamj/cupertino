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
    @Test("appliesFilter contains exactly apple-docs + packages")
    func appliesFilterMembership() {
        #expect(Search.PlatformFilterScope.appliesFilter == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.packages,
        ])
    }

    @Test("silentlyIgnoresFilter covers the 7 unaware sources")
    func silentlyIgnoresFilterMembership() {
        // appleSampleCode is an alias of samples that the unified search
        // tool routes to handleSearchSamples — listed here so dispatchSources
        // can map either spelling deterministically.
        #expect(Search.PlatformFilterScope.silentlyIgnoresFilter == [
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleSampleCode,
        ])
    }

    @Test("appliesFilter and silentlyIgnoresFilter are disjoint")
    func bucketsDisjoint() {
        let overlap = Search.PlatformFilterScope.appliesFilter
            .intersection(Search.PlatformFilterScope.silentlyIgnoresFilter)
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
        let result = Search.PlatformFilterScope.partitionForNotice(contributingSources: [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.packages,
            Shared.Constants.SourcePrefix.swiftEvolution,
        ])
        #expect(result.filtered == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.packages,
        ])
        #expect(result.unfiltered == [
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
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

    @Test("All-unaware contributing list partitions with empty filtered")
    func allUnaware() {
        let result = Search.PlatformFilterScope.partitionForNotice(contributingSources: [
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
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

    @Test("Unknown source returns empty list (tool throws later)")
    func unknownSourceReturnsEmpty() {
        let result = Search.PlatformFilterScope.dispatchSources(for: "no-such-source")
        #expect(result.isEmpty)
    }
}

@Suite("#226 — Search.PlatformFilterScope.partialNoticeMarkdown")
struct Issue226PartialNoticeMarkdownTests {
    @Test("Empty platform descriptions returns nil (no filter intended)")
    func noPlatformDescriptionsReturnsNil() {
        let result = Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: [],
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        )
        #expect(result == nil)
    }

    @Test("All-aware contributing list returns nil (no notice needed)")
    func allAwareReturnsNil() {
        let result = Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            contributingSources: [
                Shared.Constants.SourcePrefix.appleDocs,
                Shared.Constants.SourcePrefix.packages,
            ]
        )
        #expect(result == nil)
    }

    @Test("Mixed-source contributing list emits notice with stable marker")
    func mixedSourceFires() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            contributingSources: [
                Shared.Constants.SourcePrefix.appleDocs,
                Shared.Constants.SourcePrefix.hig,
            ]
        ))
        // Stable marker — AI clients grep for this rather than parsing.
        #expect(result.contains("platform_filter_partial"))
        #expect(result.contains("min_ios=18.0"))
        #expect(result.contains(Shared.Constants.SourcePrefix.appleDocs))
        #expect(result.contains(Shared.Constants.SourcePrefix.hig))
    }

    @Test("All-unaware contributing list still fires (filter completely ignored)")
    func allUnawareFires() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            contributingSources: [
                Shared.Constants.SourcePrefix.hig,
                Shared.Constants.SourcePrefix.swiftEvolution,
            ]
        ))
        #expect(result.contains("platform_filter_partial"))
        // When no source honoured the filter we still want to be honest
        // about what happened — message names the unfiltered list.
        #expect(result.contains(Shared.Constants.SourcePrefix.hig))
        #expect(result.contains(Shared.Constants.SourcePrefix.swiftEvolution))
    }

    @Test("Multiple platform descriptions are all listed")
    func multiplePlatforms() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0", "min_macos=14.0"],
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        ))
        #expect(result.contains("min_ios=18.0"))
        #expect(result.contains("min_macos=14.0"))
    }

    @Test("Output is a markdown blockquote (starts with '> ')")
    func outputIsBlockquote() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        ))
        #expect(result.hasPrefix("> "))
    }

    @Test("Output ends with blank-line separator (clean prepend)")
    func outputEndsWithBlankLine() throws {
        let result = try #require(Search.PlatformFilterScope.partialNoticeMarkdown(
            platformDescriptions: ["min_ios=18.0"],
            contributingSources: [Shared.Constants.SourcePrefix.hig]
        ))
        // Trailing "\n\n" so prepending to existing markdown produces a
        // clean separation between the notice and the search results body.
        #expect(result.hasSuffix("\n\n"))
    }
}
