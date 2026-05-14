import Foundation
import SharedConstants
// MARK: - Frameworks Markdown Formatter

extension Services.Formatter.Frameworks {
    /// Formats framework list as markdown
    public struct Markdown: Services.Formatter.Result {
        private let totalDocs: Int

        public init(totalDocs: Int) {
            self.totalDocs = totalDocs
        }

        public func format(_ frameworks: [String: Int]) -> String {
            var output = "# Available Frameworks\n\n"
            output += "Total documents: **\(totalDocs)**\n\n"

            if frameworks.isEmpty {
                let cmd = "\(Shared.Constants.App.commandName) \(Shared.Constants.Command.buildIndex)"
                output += Shared.Constants.Search.messageNoFrameworks(buildIndexCommand: cmd)
                return output
            }

            output += "| Framework | Documents |\n"
            output += "|-----------|----------:|\n"

            // Sort by document count (descending)
            for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
                output += "| `\(framework)` | \(count) |\n"
            }

            // Footer: tips and guidance
            let footer = Services.Formatter.Footer.Search.singleSource(Shared.Constants.SourcePrefix.appleDocs)
            output += footer.formatMarkdown()

            return output
        }
    }
}
