import Foundation

// MARK: - Footer Text Formatter

extension Services.Formatter.Footer {
    /// Formats footer items as plain text (CLI)
    public struct Text: Formattable {
        public init() {}

        public func format(_ items: [Item]) -> String {
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
}
