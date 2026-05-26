import Foundation

// MARK: - Footer Markdown Formatter

extension Services.Formatter.Footer {
    /// Formats footer items as markdown
    public struct Markdown: Formattable {
        public init() {}

        public func format(_ items: [Item]) -> String {
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

                case .allSourcesDiscovery:
                    // #1045 Gap 2: rendered as a small italicized note
                    // at the bottom — discovery only, not actionable
                    // (the actionable tip is `.sourceTip` above).
                    if let emoji = item.emoji {
                        output += "_\(emoji) \(item.content)_\n\n"
                    } else {
                        output += "_\(item.content)_\n\n"
                    }

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
}
