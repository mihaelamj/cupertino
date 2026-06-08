import Foundation
import SearchModels

// MARK: - Documents Markdown Formatter

extension Services.Formatter.Documents {
    public struct Markdown: Services.Formatter.Result {
        public init() {}

        public func format(_ page: Search.DocumentListPage) -> String {
            var output = "# Documents in `\(page.framework)`\n\n"
            output += "Source: `\(page.source)`  \n"
            output += "Showing \(page.documents.count) of \(page.total) documents "
            output += "(offset \(page.offset), limit \(page.limit)).\n\n"

            guard !page.documents.isEmpty else {
                output += "_No documents found._"
                return output
            }

            output += "| Title | Kind | URI |\n"
            output += "|-------|------|-----|\n"

            for document in page.documents {
                output += "| \(escape(document.title)) | `\(escape(document.kind))` | `\(escape(document.uri))` |\n"
            }

            return output
        }

        private func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "|", with: "\\|")
        }
    }
}
