import Foundation
import SampleIndex
import Search
import SharedConstants
import SharedCore

// MARK: - Unified Search Text Formatter

extension Services.Formatter.Unified {
    /// Formats unified search results as plain text for CLI output
    public struct Text: Services.Formatter.Result {
        private let query: String
        private let framework: String?
        private let config: Services.Formatter.Config

        public init(query: String, framework: String?, config: Services.Formatter.Config = .cliDefault) {
            self.query = query
            self.framework = framework
            self.config = config
        }

        public func format(_ input: Services.Formatter.Unified.Input) -> String {
            var output = "# \(query)\n\n"

            if let framework {
                output += "_Filtered to framework: \(framework)_\n\n"
            }

            let sourceCount = input.nonEmptySourceCount
            let plural = sourceCount == 1 ? "" : "s"
            output += "**Total: \(input.totalCount) results** found in \(sourceCount) source\(plural)\n\n"

            // Iterate all sources in unified order
            for (index, section) in input.allSources.enumerated() {
                let sourceNumber = index + 1
                let count = section.count
                let header = "## \(sourceNumber). \(section.info.name) (\(count)) "
                output += "\(header)\(section.info.emoji) `--source \(section.info.key)`\n\n"

                if section.isSampleSource {
                    output += formatSampleResults(section.sampleResults, sourceNumber: sourceNumber)
                } else {
                    output += formatDocResults(section.docResults, sourceNumber: sourceNumber)
                }
            }

            if input.totalCount == 0 {
                output += "_No results found across any source._\n\n"
            }

            // Footer: teasers for sources with more results, tips and guidance
            output += "---\n\n"

            // Show teasers for sources that hit the limit
            if let teasers = input.sourceTeasers {
                output += "**More results available:**\n"
                for teaser in teasers {
                    output += "- \(teaser.displayName): use `source: \(teaser.sourcePrefix)` for more\n"
                }
                output += "\n"
            }

            // Standard tips (using shared constants for consistency with MCP)
            let sources = Shared.Constants.Search.availableSources.joined(separator: ", ")
            output += "_To narrow results, use source parameter: \(sources)_\n\n"
            output += Shared.Constants.Search.tipSemanticSearch + "\n\n"
            output += Shared.Constants.Search.tipPlatformFilters + "\n"

            return output
        }

        private func formatDocResults(_ results: [Search.Result], sourceNumber: Int) -> String {
            var output = ""
            for (index, result) in results.enumerated() {
                let resultNumber = index + 1
                output += "### \(sourceNumber).\(resultNumber) \(result.title.cleanedForDisplay)\n"
                let maxLen = Shared.Constants.Limit.summaryTruncationLength
                let summary = result.cleanedSummary.cleanedForDisplay.truncated(to: maxLen)
                if !summary.isEmpty {
                    output += "\(summary)\n"
                }
                output += "- **URI:** `\(result.uri)`\n"
                if config.showAvailability,
                   let availability = result.availabilityString, !availability.isEmpty {
                    output += "- **Availability:** \(availability)\n"
                }
                // (#81) Show matched symbols from AST extraction
                if let symbols = result.matchedSymbols, !symbols.isEmpty {
                    let symbolStr = symbols.map { "`\($0.displayString)`" }.joined(separator: ", ")
                    output += "- **Symbols:** \(symbolStr)\n"
                }
                output += "\n"
            }
            return output
        }

        private func formatSampleResults(_ projects: [Sample.Index.Project], sourceNumber: Int) -> String {
            var output = ""
            for (index, project) in projects.enumerated() {
                let resultNumber = index + 1
                output += "### \(sourceNumber).\(resultNumber) \(project.title)\n"
                let maxLen = Shared.Constants.Limit.summaryTruncationLength
                let desc = project.description.cleanedForDisplay.truncated(to: maxLen)
                if !desc.isEmpty {
                    output += "\(desc)\n"
                }
                output += "- **ID:** `\(project.id)`\n\n"
            }
            return output
        }
    }
}
