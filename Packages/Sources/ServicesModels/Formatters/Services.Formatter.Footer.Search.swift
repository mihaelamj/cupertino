import Foundation
import SharedConstants

// MARK: - Footer Search

extension Services.Formatter.Footer {
    /// Collects all footer content for search results
    public struct Search: Sendable, Provider {
        /// Current source being searched (nil = all sources)
        public let currentSource: String?

        /// Teaser results from other sources
        public let teasers: Services.Formatter.TeaserResults?

        /// Whether to show semantic search tip
        public let showSemanticTip: Bool

        /// Whether to show platform filter tip
        public let showPlatformTip: Bool

        /// Custom footer items
        public let customItems: [Item]

        /// #1042 Cluster 2: composition-root-supplied list of source IDs
        /// for the "💡 To narrow results, use `source` parameter: …" tip.
        /// When nil, falls back to `Shared.Constants.Search.availableSources`
        /// (the historical static literal). A registry-aware composition
        /// root supplies the list from `makeProductionSourceRegistry().allEnabled.map(\.definition.id)`,
        /// so a new registered source's id appears in the tip without
        /// editing the static literal.
        public let availableSources: [String]?

        /// #1045 Gap 2: sources whose rows actually appeared in this
        /// response. Drives the actionable top-of-footer tip (e.g.
        /// "Sources with results: apple-docs, hig"). When nil, the
        /// formatter falls back to the legacy tip (the full
        /// availableSources list joined). The "all sources" discovery
        /// block at the BOTTOM of the footer is always present
        /// regardless — that's the "you can always try X" affordance.
        public let contributingSources: [String]?

        /// #1045 Gap 2: sources the user explicitly excluded from this
        /// search (today there's no `--exclude` CLI flag; the field
        /// future-proofs the formatter so when one lands, excluded
        /// sources stop appearing in the "other sources you can try"
        /// suggestions). Default `[]` — no exclusions.
        public let excludedSources: Set<String>

        public init(
            currentSource: String? = nil,
            teasers: Services.Formatter.TeaserResults? = nil,
            showSemanticTip: Bool = true,
            showPlatformTip: Bool = true,
            customItems: [Item] = [],
            availableSources: [String]? = nil,
            contributingSources: [String]? = nil,
            excludedSources: Set<String> = []
        ) {
            self.currentSource = currentSource
            self.teasers = teasers
            self.showSemanticTip = showSemanticTip
            self.showPlatformTip = showPlatformTip
            self.customItems = customItems
            self.availableSources = availableSources
            self.contributingSources = contributingSources
            self.excludedSources = excludedSources
        }

        public func makeFooter() -> [Item] {
            var items: [Item] = []
            let registeredSources = availableSources ?? Shared.Constants.Search.availableSources

            // 1. Actionable source tip (top of footer). #1045 Gap 2:
            //    if the caller supplied `contributingSources`, the tip
            //    names only those (smallest signal, highest relevance).
            //    Otherwise fall back to the legacy "full list" tip for
            //    callers that haven't migrated.
            let actionableTip = makeActionableSourceTip(
                currentSource: currentSource,
                contributingSources: contributingSources,
                registeredSources: registeredSources,
                excludedSources: excludedSources
            )
            items.append(Item(
                kind: .sourceTip,
                content: actionableTip,
                emoji: "💡"
            ))

            // 2. Teasers (if available and not searching all)
            if let teasers, !teasers.isEmpty {
                items.append(contentsOf: makeTeaserItems(teasers))
            }

            // 3. Semantic search tip
            if showSemanticTip {
                items.append(Item(
                    kind: .semanticTip,
                    content: Shared.Constants.Search.tipSemanticSearch,
                    emoji: "🔍"
                ))
            }

            // 4. Platform filter tip
            if showPlatformTip {
                items.append(Item(
                    kind: .platformTip,
                    content: Shared.Constants.Search.tipPlatformFilters,
                    emoji: "📱"
                ))
            }

            // 5. Custom items
            items.append(contentsOf: customItems)

            // 6. "All sources" discovery block (bottom of footer).
            //    #1045 Gap 2: ALWAYS present (per user direction
            //    "always mention there are other sources at the
            //    bottom"). Compact rendering — middot-joined — so the
            //    full registered list doesn't crowd the response even
            //    as the set grows. Excludes the current source (for
            //    single-source mode) + user-excluded sources.
            let discoveryList = registeredSources
                .filter { $0 != currentSource && !excludedSources.contains($0) }
            if !discoveryList.isEmpty {
                items.append(Item(
                    kind: .allSourcesDiscovery,
                    content: "All sources you can search: \(discoveryList.joined(separator: " · "))",
                    emoji: "📚"
                ))
            }

            return items
        }

        /// Build the actionable tip text. When `contributingSources` is
        /// supplied (post-#1045 Gap 2), the tip names only the sources
        /// that actually had results; otherwise falls back to the
        /// pre-#1045 "full registered list" tip for callers that haven't
        /// migrated.
        private func makeActionableSourceTip(
            currentSource: String?,
            contributingSources: [String]?,
            registeredSources: [String],
            excludedSources: Set<String>
        ) -> String {
            if let contributingSources, !contributingSources.isEmpty {
                let names = contributingSources
                    .filter { !excludedSources.contains($0) }
                    .joined(separator: ", ")
                if currentSource == nil {
                    return "_Sources with results in this response: \(names). Narrow further with `--source <name>`._"
                }
                return "_Other sources with relevant results: \(names)._"
            }
            // Legacy fallback (pre-Gap-2 callers).
            let sources = registeredSources
                .filter { $0 != currentSource && !excludedSources.contains($0) }
                .joined(separator: ", ")
            if currentSource == nil {
                return "_To narrow results, use `source` parameter: \(sources)_"
            }
            return Shared.Constants.Search.tipOtherSources(excluding: currentSource)
        }

        private func makeTeaserItems(_ teasers: Services.Formatter.TeaserResults) -> [Item] {
            teasers.allSources.map { source in
                let titleList = source.titles.map { "- \($0)" }.joined(separator: "\n")
                return Item(
                    kind: .teaser,
                    title: "Also in \(source.displayName)",
                    content: "\(titleList)\n_→ Use `source: \(source.sourcePrefix)`_",
                    emoji: source.emoji
                )
            }
        }
    }
}

// MARK: - Convenience Constructors

extension Services.Formatter.Footer.Search {
    /// Create footer for unified search (all sources).
    /// #1042 audit + wiring batch 5: `availableSources` parameter for
    /// the registry-derived "narrow with --source: …" tip. When nil,
    /// the footer falls back to `Shared.Constants.Search.availableSources`.
    public static func unified(
        showSemanticTip: Bool = true,
        showPlatformTip: Bool = true,
        availableSources: [String]? = nil,
        contributingSources: [String]? = nil,
        excludedSources: Set<String> = []
    ) -> Services.Formatter.Footer.Search {
        Services.Formatter.Footer.Search(
            currentSource: nil,
            teasers: nil,
            showSemanticTip: showSemanticTip,
            showPlatformTip: showPlatformTip,
            availableSources: availableSources,
            contributingSources: contributingSources,
            excludedSources: excludedSources
        )
    }

    /// Create footer for single-source search.
    /// #1042 audit + wiring batch 5: same `availableSources`
    /// composition-root injection point as `unified(...)`.
    public static func singleSource(
        _ source: String,
        teasers: Services.Formatter.TeaserResults? = nil,
        showSemanticTip: Bool = true,
        showPlatformTip: Bool = true,
        availableSources: [String]? = nil,
        contributingSources: [String]? = nil,
        excludedSources: Set<String> = []
    ) -> Services.Formatter.Footer.Search {
        Services.Formatter.Footer.Search(
            currentSource: source,
            teasers: teasers,
            showSemanticTip: showSemanticTip,
            showPlatformTip: showPlatformTip,
            availableSources: availableSources,
            contributingSources: contributingSources,
            excludedSources: excludedSources
        )
    }

    /// Format using any Formattable formatter
    public func format(with formatter: some Services.Formatter.Footer.Formattable) -> String {
        formatter.format(makeFooter())
    }

    /// Format as markdown
    public func formatMarkdown() -> String {
        format(with: Services.Formatter.Footer.Markdown())
    }

    /// Format as plain text
    public func formatText() -> String {
        format(with: Services.Formatter.Footer.Text())
    }
}
