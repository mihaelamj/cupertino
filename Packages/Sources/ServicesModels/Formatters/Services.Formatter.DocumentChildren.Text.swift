import Foundation
import SearchModels

// MARK: - Document Children Text Formatter

extension Services.Formatter.DocumentChildren {
    public struct Text: Services.Formatter.Result {
        public init() {}

        public func format(_ page: Search.DocumentChildrenPage) -> String {
            if page.children.isEmpty {
                return "No children found for \(page.parentURI)."
            }

            var output = "Children of \(page.parentURI): \(page.children.count)\n\n"

            for child in page.children {
                output += "\(child.title)\n"
                output += "  URI: \(child.uri)\n"
                output += "  Kind: \(child.kind)\n"
                output += "  Has children: \(child.hasChildren ? "yes" : "no")\n"
            }

            return output
        }
    }
}
