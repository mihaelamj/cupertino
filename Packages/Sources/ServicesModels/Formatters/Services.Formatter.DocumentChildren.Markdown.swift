import Foundation
import SearchModels

// MARK: - Document Children Markdown Formatter

extension Services.Formatter.DocumentChildren {
    public struct Markdown: Services.Formatter.Result {
        public init() {}

        public func format(_ page: Search.DocumentChildrenPage) -> String {
            var output = "# Children of `\(escape(page.parentURI))`\n\n"
            output += "Source: `\(page.source)`  \n"
            output += "Children: \(page.children.count)\n\n"

            guard !page.children.isEmpty else {
                output += "_No children found._"
                return output
            }

            output += "| Title | Kind | Has Children | URI |\n"
            output += "|-------|------|--------------|-----|\n"

            for child in page.children {
                output += "| \(escape(child.title)) | `\(escape(child.kind))` | \(child.hasChildren ? "yes" : "no") | `\(escape(child.uri))` |\n"
            }

            return output
        }

        private func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "|", with: "\\|")
        }
    }
}
