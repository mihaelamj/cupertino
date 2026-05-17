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
        /// Sources whose tool handler applies the platform filter on
        /// `min_*` columns at MCP dispatch time. A non-matching row is
        /// excluded from the response. Apple-archive uses the same
        /// `docs_metadata` table but legacy archive guides rarely carry
        /// populated `min_*` columns — empirically the filter is a no-op
        /// there, so we treat it as *not* applying for the notice
        /// purposes (the notice would otherwise lie).
        public static let appliesFilter: Set<String> = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.packages,
        ]

        /// Sources whose tool handler does **not** apply the platform
        /// filter at MCP dispatch time today. Either:
        /// - Source has no platform-availability axis (article-shaped:
        ///   `hig`, `swift-evolution`, `swift-org`, `swift-book`,
        ///   `apple-archive`), so the filter is structurally not
        ///   applicable.
        /// - Or source's data carries `min_*` columns but the tool
        ///   handler silently drops the filter at the MCP boundary
        ///   (`samples` today — `handleSearchSamples` in
        ///   `CompositeToolProvider.swift` does not thread platform args
        ///   into `Sample.Search.Query`).
        ///
        /// The notice surfaces this fact to AI clients so they cannot
        /// assume "filter applied uniformly across the result set."
        public static let silentlyIgnoresFilter: Set<String> = [
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleSampleCode,
        ]

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
                if appliesFilter.contains(source) {
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

        /// Resolve the source parameter of the unified MCP `search` tool
        /// into the list of sources that will actually contribute to the
        /// result set. Used by the notice helper before dispatch so the
        /// caller can decide whether to fire the notice without waiting
        /// for the search to run.
        ///
        /// - `nil`, `"all"`, empty string → fan-out (every source)
        /// - any of `appleSampleCode` / `samples` → `[samples]` (alias
        ///   canonicalisation; the data lives under the `samples` prefix)
        /// - any known source identifier → `[source]`
        /// - unknown source identifier → empty list (the tool throws
        ///   later — no notice to fire pre-throw)
        public static func dispatchSources(for source: String?) -> [String] {
            guard let source, !source.isEmpty, source != "all" else {
                return allFanOutSources
            }
            // Canonicalise sample-code alias to its prefix.
            if source == Shared.Constants.SourcePrefix.appleSampleCode {
                return [Shared.Constants.SourcePrefix.samples]
            }
            if appliesFilter.contains(source) || silentlyIgnoresFilter.contains(source) {
                return [source]
            }
            return []
        }

        /// Produce the `info.platform_filter_partial` markdown notice
        /// block prepended to MCP tool responses when the user passes
        /// platform filters AND at least one contributing source does
        /// not honour them.
        ///
        /// Returns `nil` when no notice is needed (no platform args set,
        /// or every contributing source honours the filter).
        ///
        /// The block is a Markdown blockquote with a stable bold marker
        /// (`**platform_filter_partial**`) at the start so AI clients
        /// reading the response can grep for the marker rather than
        /// parsing prose.
        public static func partialNoticeMarkdown(
            platformDescriptions: [String],
            contributingSources: [String]
        ) -> String? {
            guard !platformDescriptions.isEmpty else { return nil }
            let parts = partitionForNotice(contributingSources: contributingSources)
            guard !parts.unfiltered.isEmpty else { return nil }
            let appliedTo = parts.filtered.isEmpty
                ? "no sources in this response"
                : parts.filtered.joined(separator: ", ")
            let notHonoured = parts.unfiltered.joined(separator: ", ")
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
