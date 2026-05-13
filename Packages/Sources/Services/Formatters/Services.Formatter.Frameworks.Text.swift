import Foundation
import SharedConstants
import SharedCore

// MARK: - Frameworks Text Formatter

extension Services.Formatter.Frameworks {
    /// Formats framework list as plain text for CLI output
    public struct Text: Services.Formatter.Result {
        private let totalDocs: Int

        public init(totalDocs: Int) {
            self.totalDocs = totalDocs
        }

        public func format(_ frameworks: [String: Int]) -> String {
            if frameworks.isEmpty {
                return "No frameworks found. Run 'cupertino save' to build the index."
            }

            var output = "Available Frameworks (\(frameworks.count) total, \(totalDocs) documents):\n\n"

            // Sort by document count (descending)
            for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
                output += "  \(framework): \(count) documents\n"
            }

            // Footer: tips and guidance
            let footer = Services.Formatter.Footer.Search.singleSource(Shared.Constants.SourcePrefix.appleDocs)
            output += footer.formatText()

            return output
        }
    }
}
