import Foundation
import SharedConstants

// MARK: - Search.PlatformFilterScope

extension Search {
    /// Single source of truth for which sources actually honour the MCP /
    /// CLI platform filter (`--platform` / `min_ios` / `min_macos` / …) at
    /// query dispatch time.
    ///
    /// **Why this matters (#226):** the MCP search-style tools accept
    /// `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos`
    /// parameters. The unified `search` tool routes to per-source handlers,
    /// not all of which apply the filter today. Pre-#226 the MCP tool
    /// response carried no signal that the user's filter was silently
    /// ignored for a subset of sources — `info.platform_filter_partial`
    /// (this type's consumers) closes that gap.
    ///
    /// **Two categories that are *not* the same:**
    /// - "Source's data shape carries `min_*` columns" — apple-docs,
    ///   packages, samples. Theoretically filterable.
    /// - "Source's MCP tool handler actually applies the filter at query
    ///   time" — today only apple-docs and packages.
    ///
    /// This type encodes the second (the user-visible behaviour), not the
    /// first. When `handleSearchSamples` is updated to thread the filter
    /// through, `samples` moves from `silentlyIgnoresFilter` to
    /// `appliesFilter` here in one edit; the notice helper picks it up
    /// automatically.
    public enum PlatformFilterScope {
        /// Sources whose `handleSearchDocs` dispatch DOES thread the
        /// `min_*` platform args through to `Search.Database.search`,
        /// causing a non-matching row to be excluded from the response.
        ///
        /// All 6 sources here route through the same handler at
        /// `CompositeToolProvider.handleSearch` lines 547-552. The filter
        /// is applied uniformly; rows with NULL `min_*` are dropped per
        /// the index's `IS NOT NULL` gate. Whether the source's data is
        /// *populated* with `min_*` values is orthogonal to whether the
        /// handler applies the filter — sparse data manifests as fewer
        /// results, not as unfiltered results.
        public static let dispatchAppliesFilter: Set<String> = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.packages,
            // #732: samples now apply the 5-field platform filter
            // natively via `Sample.Index.Database.searchProjects`
            // (and `Sample.Search.Query` carries the 5 fields end-to-end).
            // Both the specific-source dispatch (handleSearchSamples) and
            // the fan-out path (UnifiedSearchService.searchSamples) thread
            // the args through.
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleSampleCode,
        ]

        /// Sources whose tool handler does **not** thread the platform
        /// filter through — the args are dropped at the MCP boundary.
        ///
        /// **Post-#732 this is just `hig`.** HIG content is design /
        /// UI guidelines (Buttons, Color, Typography, Accessibility)
        /// with no version-availability axis on the underlying data.
        /// Filtering structurally doesn't fit; the notice fires for any
        /// `source=hig` dispatch + platform filter to tell AI clients
        /// the filter was honoured everywhere except HIG.
        ///
        /// `handleSearchHIG(query:framework:limit:)` keeps its
        /// 3-argument signature — adding `min_*` parameters would
        /// expose an interface that produces zero results by design.
        public static let dispatchDropsFilter: Set<String> = [
            Shared.Constants.SourcePrefix.hig,
        ]

        // MARK: - Legacy compatibility (deprecated aliases)

        /// Deprecated: use `dispatchAppliesFilter` instead. Retained
        /// as a transitional alias to avoid breaking the test suite
        /// during the critic-pass rename in this PR; will be removed
        /// before merge.
        @available(*, deprecated, renamed: "dispatchAppliesFilter")
        public static var appliesFilter: Set<String> {
            dispatchAppliesFilter
        }

        /// Deprecated: use `dispatchDropsFilter` instead. The previous
        /// name baked in the wrong classification of apple-archive +
        /// swift-evolution / swift-org / swift-book (those go through
        /// `handleSearchDocs` and DO apply the filter; the previous
        /// classification told the user otherwise).
        @available(*, deprecated, renamed: "dispatchDropsFilter")
        public static var silentlyIgnoresFilter: Set<String> {
            dispatchDropsFilter
        }

        /// Filter a list of contributing source identifiers down to those
        /// that don't honour the platform filter. Used by the notice
        /// helper to enumerate the sources the user should know were not
        /// filtered.
        ///
        /// Sources not appearing in either bucket are conservatively
        /// treated as ignored — if the user filtered and the source is
        /// unrecognised, the notice fires rather than risking silent
        /// inaccuracy.
        public static func partitionForNotice(
            contributingSources: [String]
        ) -> (filtered: [String], unfiltered: [String]) {
            var filtered: [String] = []
            var unfiltered: [String] = []
            for source in contributingSources {
                if dispatchAppliesFilter.contains(source) {
                    filtered.append(source)
                } else {
                    unfiltered.append(source)
                }
            }
            return (filtered: filtered, unfiltered: unfiltered)
        }

        /// Sources that the unified MCP `search` tool fans out to when no
        /// explicit `source` parameter is set. Used by the notice helper
        /// to enumerate which sources participate in a fan-out call so the
        /// partial-filter notice can name them honestly.
        public static let allFanOutSources: [String] = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.packages,
            Shared.Constants.SourcePrefix.samples,
        ]

        /// Describes how the unified `search` tool will route the user's
        /// request. Drives the notice decision: fan-out via
        /// `handleSearchAll` drops platform args silently for ALL
        /// sources, so the notice must fire for every contributing
        /// source — different from the specific-source case where only
        /// `dispatchDropsFilter` sources need calling out.
        public enum Dispatch: Sendable, Equatable {
            /// Specific source dispatch: routes to `handleSearchSamples` /
            /// `handleSearchHIG` / `handleSearchDocs`. Whether the filter
            /// is honoured depends on which sub-handler runs.
            case singleSource(String)
            /// Fan-out dispatch (source = nil / empty / `"all"`):
            /// routes to `handleSearchAll`, which today does NOT thread
            /// platform args through to any of its 8 fetcher sources.
            /// Every contributing source is unfiltered.
            case fanOut
        }

        /// Resolve the user's `source` parameter into a `Dispatch`
        /// classification + the list of sources that will contribute to
        /// the result set. Used by the notice helper to decide what to
        /// say.
        ///
        /// - `nil`, `"all"`, empty string → `.fanOut` over all 8 sources
        /// - `appleSampleCode` alias → `.singleSource(samples)` (canonicalised)
        /// - any known specific source → `.singleSource(source)`
        /// - unknown source → `.singleSource(source)` returned verbatim
        ///   (the tool throws later; the notice would be moot)
        public static func dispatch(
            for source: String?
        ) -> (kind: Dispatch, sources: [String]) {
            guard let source, !source.isEmpty, source != "all" else {
                return (.fanOut, allFanOutSources)
            }
            // Canonicalise sample-code alias to its prefix.
            if source == Shared.Constants.SourcePrefix.appleSampleCode {
                return (
                    .singleSource(Shared.Constants.SourcePrefix.samples),
                    [Shared.Constants.SourcePrefix.samples]
                )
            }
            return (.singleSource(source), [source])
        }

        /// Deprecated alias used during the critic-pass rename. Returns
        /// the source list from `dispatch(for:)` for callers that don't
        /// need the dispatch kind.
        @available(*, deprecated, message: "Use dispatch(for:) instead — the dispatch kind matters for the notice decision.")
        public static func dispatchSources(for source: String?) -> [String] {
            dispatch(for: source).sources
        }

        /// Produce the `info.platform_filter_partial` markdown notice
        /// block prepended to MCP tool responses when the user passes
        /// platform filters AND the dispatch path produces unfiltered
        /// rows.
        ///
        /// Returns `nil` when no notice is needed:
        /// - No platform descriptions provided
        /// - Single-source dispatch through a handler that applies the
        ///   filter (apple-docs / packages / etc. via handleSearchDocs)
        ///
        /// Fires when:
        /// - `.fanOut` + any platform descriptions — `handleSearchAll`
        ///   drops platform args for every source today
        /// - `.singleSource(s)` where `s` ∈ `dispatchDropsFilter`
        ///
        /// The block is a Markdown blockquote with a stable bold marker
        /// (`**platform_filter_partial**`) at the start so AI clients
        /// reading the response can grep for the marker rather than
        /// parsing prose.
        public static func partialNoticeMarkdown(
            platformDescriptions: [String],
            dispatch: Dispatch,
            contributingSources: [String]
        ) -> String? {
            guard !platformDescriptions.isEmpty else { return nil }
            let (filtered, unfiltered): ([String], [String]) = {
                switch dispatch {
                case .fanOut:
                    // handleSearchAll drops platform args for every source today.
                    // Every contributing source is reported as unfiltered.
                    return ([], contributingSources)
                case .singleSource:
                    let parts = partitionForNotice(contributingSources: contributingSources)
                    return (parts.filtered, parts.unfiltered)
                }
            }()
            guard !unfiltered.isEmpty else { return nil }
            let appliedTo = filtered.isEmpty
                ? "no sources in this response"
                : filtered.joined(separator: ", ")
            let notHonoured = unfiltered.joined(separator: ", ")
            // Trailing "\n\n" gives a clean blank-line separation when the
            // notice is prepended to existing markdown content. Built via
            // explicit concatenation rather than relying on multi-line
            // literal newline semantics — Swift trims the trailing newline
            // before the closing `"""`, so a literal-only build produces
            // `\n` not `\n\n`.
            let line = "> ℹ️ **platform_filter_partial** — Your platform filter (\(platformDescriptions.joined(separator: ", "))) was honoured for: \(appliedTo). The following sources do not honour platform filters and are included unfiltered in this response: \(notHonoured)."
            return line + "\n\n"
        }
    }
}
