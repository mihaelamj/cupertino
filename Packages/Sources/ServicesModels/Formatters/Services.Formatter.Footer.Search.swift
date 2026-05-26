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

        /// 2026-05-26 audit Finding 6.0: registry-supplied list of
        /// source IDs for the "💡 To narrow results, use `source`
        /// parameter: …" tip. Non-optional + no fallback — every
        /// caller MUST supply the list from
        /// `CupertinoComposition.makeProductionSourceRegistry().allEnabled.map(\.definition.id)`
        /// (or equivalent registry iteration). Pre-fix this was
        /// optional and the formatter silently fell back to the
        /// `Shared.Constants.Search.availableSources` static literal
        /// — a maintenance trap where a future PR that forgot to
        /// wire `availableSources` would silently omit any new
        /// shipped source from the footer.
        public let availableSources: [String]

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
            availableSources: [String],
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
            let registeredSources = availableSources

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
            // 2026-05-26 audit Finding 6.0: `tipOtherSources` previously
            // delegated to `Shared.Constants.Search.otherSources(excluding:)`
            // which iterated the deleted static literal. Inline the
            // same computation against the (non-optional) registered
            // list so the tip honours the caller-supplied scope.
            let others = registeredSources
                .filter { $0 != (currentSource ?? "") }
                .joined(separator: ", ")
            return "💡 **Other sources:** \(others), or `all`"
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
    /// 2026-05-26 audit Finding 6.0: `availableSources` is non-optional;
    /// every caller MUST supply the registry-derived list (typically
    /// `CupertinoComposition.makeProductionSourceRegistry().allEnabled.map(\.definition.id)`).
    public static func unified(
        showSemanticTip: Bool = true,
        showPlatformTip: Bool = true,
        availableSources: [String],
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
    /// 2026-05-26 audit Finding 6.0: `availableSources` is non-optional;
    /// callers MUST supply the registry-derived list.
    public static func singleSource(
        _ source: String,
        teasers: Services.Formatter.TeaserResults? = nil,
        showSemanticTip: Bool = true,
        showPlatformTip: Bool = true,
        availableSources: [String],
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
