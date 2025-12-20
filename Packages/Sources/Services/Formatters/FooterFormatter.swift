import Foundation
import SampleIndex
import Search
import Shared

// MARK: - Footer Types

/// Types of footer content in search results
public enum FooterKind: String, Sendable, CaseIterable {
    case sourceTip // Tip about other sources
    case semanticTip // Tip about semantic search tools
    case teaser // Preview results from other sources
    case platformTip // Tip about platform filters
    case custom // Custom footer content
}

/// A single footer item
public struct FooterItem: Sendable {
    public let kind: FooterKind
    public let title: String?
    public let content: String
    public let emoji: String?

    public init(
        kind: FooterKind,
        title: String? = nil,
        content: String,
        emoji: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.content = content
        self.emoji = emoji
    }
}

// MARK: - Footer Protocol

/// Protocol for types that can provide footer content
public protocol FooterProvider: Sendable {
    /// Generate footer items for this context
    func makeFooter() -> [FooterItem]
}

// MARK: - Search Footer

/// Collects all footer content for search results
public struct SearchFooter: Sendable, FooterProvider {
    /// Current source being searched (nil = all sources)
    public let currentSource: String?

    /// Teaser results from other sources
    public let teasers: TeaserResults?

    /// Whether to show semantic search tip
    public let showSemanticTip: Bool

    /// Whether to show platform filter tip
    public let showPlatformTip: Bool

    /// Custom footer items
    public let customItems: [FooterItem]

    public init(
        currentSource: String? = nil,
        teasers: TeaserResults? = nil,
        showSemanticTip: Bool = true,
        showPlatformTip: Bool = true,
        customItems: [FooterItem] = []
    ) {
        self.currentSource = currentSource
        self.teasers = teasers
        self.showSemanticTip = showSemanticTip
        self.showPlatformTip = showPlatformTip
        self.customItems = customItems
    }

    public func makeFooter() -> [FooterItem] {
        var items: [FooterItem] = []

        // 1. Source tip (always show)
        let sources = Shared.Constants.Search.availableSources.joined(separator: ", ")
        let sourceTip = if currentSource == nil {
            // Unified search - show how to narrow
            "_To narrow results, use `source` parameter: \(sources)_"
        } else {
            // Single source - show other sources
            Shared.Constants.Search.tipOtherSources(excluding: currentSource)
        }
        items.append(FooterItem(
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
            items.append(FooterItem(
                kind: .semanticTip,
                content: Shared.Constants.Search.tipSemanticSearch,
                emoji: "🔍"
            ))
        }

        // 4. Platform filter tip
        if showPlatformTip {
            items.append(FooterItem(
                kind: .platformTip,
                content: Shared.Constants.Search.tipPlatformFilters,
                emoji: "📱"
            ))
        }

        // 5. Custom items
        items.append(contentsOf: customItems)

        return items
    }

    private func makeTeaserItems(_ teasers: TeaserResults) -> [FooterItem] {
        teasers.allSources.map { source in
            let titleList = source.titles.map { "- \($0)" }.joined(separator: "\n")
            return FooterItem(
                kind: .teaser,
                title: "Also in \(source.displayName)",
                content: "\(titleList)\n_→ Use `source: \(source.sourcePrefix)`_",
                emoji: source.emoji
            )
        }
    }
}

// MARK: - Footer Formatter Protocol

/// Protocol for formatting footer content
public protocol FooterFormattable {
    func format(_ items: [FooterItem]) -> String
}

// MARK: - Markdown Footer Formatter

/// Formats footer items as markdown
public struct MarkdownFooterFormatter: FooterFormattable {
    public init() {}

    public func format(_ items: [FooterItem]) -> String {
        guard !items.isEmpty else { return "" }

        var output = "\n---\n\n"

        for item in items {
            switch item.kind {
            case .teaser:
                if let emoji = item.emoji, let title = item.title {
                    output += "\(emoji) **\(title):**\n"
                }
                output += item.content + "\n\n"

            case .sourceTip, .semanticTip, .platformTip:
                output += item.content + "\n\n"

            case .custom:
                if let title = item.title {
                    output += "**\(title):** "
                }
                output += item.content + "\n\n"
            }
        }

        return output.trimmingCharacters(in: .newlines) + "\n"
    }
}

// MARK: - Text Footer Formatter

/// Formats footer items as plain text (CLI)
public struct TextFooterFormatter: FooterFormattable {
    public init() {}

    public func format(_ items: [FooterItem]) -> String {
        guard !items.isEmpty else { return "" }

        var output = "\n" + String(repeating: "-", count: 40) + "\n"

        for item in items {
            switch item.kind {
            case .teaser:
                if let title = item.title {
                    output += "\(title):\n"
                }
                output += stripMarkdown(item.content, preserveArrow: true) + "\n\n"

            case .sourceTip, .semanticTip, .platformTip:
                output += stripMarkdown(item.content) + "\n\n"

            case .custom:
                if let title = item.title {
                    output += "\(title): "
                }
                output += item.content + "\n\n"
            }
        }

        return output.trimmingCharacters(in: .newlines) + "\n"
    }

    /// Strips markdown formatting for plain text output
    private func stripMarkdown(_ text: String, preserveArrow: Bool = false) -> String {
        var result = text
        if preserveArrow {
            result = result.replacingOccurrences(of: "_→", with: "→")
        }
        return result
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
    }
}

// MARK: - Convenience Extensions

public extension SearchFooter {
    /// Create footer for unified search (all sources)
    static func unified(showSemanticTip: Bool = true, showPlatformTip: Bool = true) -> SearchFooter {
        SearchFooter(
            currentSource: nil,
            teasers: nil,
            showSemanticTip: showSemanticTip,
            showPlatformTip: showPlatformTip
        )
    }

    /// Create footer for single-source search
    static func singleSource(
        _ source: String,
        teasers: TeaserResults? = nil,
        showSemanticTip: Bool = true,
        showPlatformTip: Bool = true
    ) -> SearchFooter {
        SearchFooter(
            currentSource: source,
            teasers: teasers,
            showSemanticTip: showSemanticTip,
            showPlatformTip: showPlatformTip
        )
    }

    /// Format using any FooterFormattable formatter
    func format(with formatter: some FooterFormattable) -> String {
        formatter.format(makeFooter())
    }

    /// Format as markdown
    func formatMarkdown() -> String {
        format(with: MarkdownFooterFormatter())
    }

    /// Format as plain text
    func formatText() -> String {
        format(with: TextFooterFormatter())
    }
}
