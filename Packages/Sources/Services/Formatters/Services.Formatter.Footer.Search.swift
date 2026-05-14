import ServicesModels
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

        public init(
            currentSource: String? = nil,
            teasers: Services.Formatter.TeaserResults? = nil,
            showSemanticTip: Bool = true,
            showPlatformTip: Bool = true,
            customItems: [Item] = []
        ) {
            self.currentSource = currentSource
            self.teasers = teasers
            self.showSemanticTip = showSemanticTip
            self.showPlatformTip = showPlatformTip
            self.customItems = customItems
        }

        public func makeFooter() -> [Item] {
            var items: [Item] = []

            // 1. Source tip (always show)
            let sources = Shared.Constants.Search.availableSources.joined(separator: ", ")
            let sourceTip = if currentSource == nil {
                // Unified search - show how to narrow
                "_To narrow results, use `source` parameter: \(sources)_"
            } else {
                // Single source - show other sources
                Shared.Constants.Search.tipOtherSources(excluding: currentSource)
            }
            items.append(Item(
                kind: .sourceTip,
                content: sourceTip,
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

            return items
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
    /// Create footer for unified search (all sources)
    public static func unified(showSemanticTip: Bool = true, showPlatformTip: Bool = true) -> Services.Formatter.Footer.Search {
        Services.Formatter.Footer.Search(
            currentSource: nil,
            teasers: nil,
            showSemanticTip: showSemanticTip,
            showPlatformTip: showPlatformTip
        )
    }

    /// Create footer for single-source search
    public static func singleSource(
        _ source: String,
        teasers: Services.Formatter.TeaserResults? = nil,
        showSemanticTip: Bool = true,
        showPlatformTip: Bool = true
    ) -> Services.Formatter.Footer.Search {
        Services.Formatter.Footer.Search(
            currentSource: source,
            teasers: teasers,
            showSemanticTip: showSemanticTip,
            showPlatformTip: showPlatformTip
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
