import Foundation
import SharedConstants

// MARK: - Frameworks Text Formatter

extension Services.Formatter.Frameworks {
    /// Formats framework list as plain text for CLI output
    public struct Text: Services.Formatter.Result {
        private let totalDocs: Int
        /// #1045 Gap 2: registry-derived source-id list for footer tips.
        private let availableSources: [String]
        /// #1041: the source IDs that actually contributed to `totalDocs`
        /// (the registry's `.listFrameworks` fan-out). Empty renders no
        /// caveat. Passed in, never hardcoded, so a new framework-scoped
        /// source appears here with zero edits to this formatter.
        private let frameworkScopedSources: [String]

        public init(totalDocs: Int, availableSources: [String], frameworkScopedSources: [String] = []) {
            self.totalDocs = totalDocs
            self.availableSources = availableSources
            self.frameworkScopedSources = frameworkScopedSources
        }

        public func format(_ frameworks: [String: Int]) -> String {
            if frameworks.isEmpty {
                return "No frameworks found. Run 'cupertino save' to build the index."
            }

            var output = "Available Frameworks (\(frameworks.count) total, \(totalDocs) documents):\n"
            if !frameworkScopedSources.isEmpty {
                output += "(counts cover the framework-scoped sources: \(frameworkScopedSources.joined(separator: " + ")))\n"
            }
            output += "\n"

            // Sort by document count (descending)
            for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
                output += "  \(framework): \(count) documents\n"
            }

            // Footer: tips and guidance
            let footer = Services.Formatter.Footer.Search.singleSource(
                Shared.Constants.SourcePrefix.appleDocs,
                availableSources: availableSources
            )
            output += footer.formatText()

            return output
        }
    }
}
