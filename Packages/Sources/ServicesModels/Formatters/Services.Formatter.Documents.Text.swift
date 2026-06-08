import Foundation
import SearchModels

// MARK: - Documents Text Formatter

extension Services.Formatter.Documents {
    public struct Text: Services.Formatter.Result {
        public init() {}

        public func format(_ page: Search.DocumentListPage) -> String {
            if page.documents.isEmpty {
                return "No documents found for \(page.source) framework \(page.framework)."
            }

            var output = "Documents in \(page.source) / \(page.framework): "
            output += "\(page.documents.count) shown of \(page.total) "
            output += "(offset \(page.offset), limit \(page.limit))\n\n"

            for document in page.documents {
                output += "\(document.title)\n"
                output += "  URI: \(document.uri)\n"
                output += "  Kind: \(document.kind)\n"
            }

            return output
        }
    }
}
