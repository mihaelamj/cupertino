import Foundation
import SampleIndex
import Search
import SharedConstants
import SharedCore
import SearchModels

// MARK: - Unified Search Markdown Formatter

extension Services.Formatter.Unified {
    /// Formats unified search results (ALL sources) as markdown
    public struct Markdown: Services.Formatter.Result {
        private let query: String
        private let framework: String?
        private let config: Services.Formatter.Config

        public init(
            query: String,
            framework: String? = nil,
            config: Services.Formatter.Config = .mcpDefault
        ) {
            self.query = query
            self.framework = framework
            self.config = config
        }

        public func format(_ input: Services.Formatter.Unified.Input) -> String {
            var output = "# Unified Search: \"\(query)\"\n\n"

            if let framework {
                output += "_Filtered to framework: **\(framework)**_\n\n"
            }

            // Tell the AI exactly what sources were searched
            let allSources = Shared.Constants.Search.availableSources.joined(separator: ", ")
            output += "_Searched ALL sources: \(allSources)_\n\n"

            let sourceCount = input.nonEmptySourceCount
            let plural = sourceCount == 1 ? "" : "s"
            output += "**Total: \(input.totalCount) results** found in \(sourceCount) source\(plural)\n\n"

            // Iterate all sources in unified order
            for section in input.allSources {
                output += "## \(section.info.emoji) \(section.info.name) (\(section.count))\n\n"
                if section.isSampleSource {
                    output += formatSampleResults(section.sampleResults)
                } else {
                    output += formatDocResults(section.docResults)
                }
            }

            // Show message if no results at all
            if input.totalCount == 0 {
                output += "_No results found across any source._\n\n"
            }

            // Footer: teasers for sources with more results, tips and guidance
            output += "\n---\n\n"

            // Show teasers for sources that hit the limit
            if let teasers = input.sourceTeasers {
                output += "**More results available:**\n"
                for teaser in teasers {
                    output += "- \(teaser.emoji) \(teaser.displayName): _use `source: \(teaser.sourcePrefix)` for more_\n"
                }
                output += "\n"
            }

            // Standard tips
            let sources = Shared.Constants.Search.availableSources.joined(separator: ", ")
            output += "_To narrow results, use `source` parameter: \(sources)_\n\n"
            output += Shared.Constants.Search.tipSemanticSearch + "\n\n"
            output += Shared.Constants.Search.tipPlatformFilters + "\n"

            return output
        }

        private func formatDocResults(_ results: [Search.Result]) -> String {
            var output = ""
            let maxLen = Shared.Constants.Limit.summaryTruncationLength
            for result in results {
                output += "- **\(result.title.cleanedForDisplay)**\n"
                let summary = result.cleanedSummary.cleanedForDisplay.truncated(to: maxLen)
                if !summary.isEmpty {
                    output += "  - \(summary)\n"
                }
                output += "  - URI: `\(result.uri)`\n"
                if config.showAvailability,
                   let availability = result.availabilityString, !availability.isEmpty {
                    output += "  - Availability: \(availability)\n"
                }
                // (#81) Show matched symbols from AST extraction
                if let symbols = result.matchedSymbols, !symbols.isEmpty {
                    let symbolStr = symbols.map { "`\($0.displayString)`" }.joined(separator: ", ")
                    output += "  - Symbols: \(symbolStr)\n"
                }
            }
            output += "\n"
            return output
        }

        private func formatSampleResults(_ projects: [Sample.Index.Project]) -> String {
            var output = ""
            let maxLen = Shared.Constants.Limit.summaryTruncationLength
            for project in projects {
                output += "- **\(project.title)**\n"
                let desc = project.description.cleanedForDisplay.truncated(to: maxLen)
                if !desc.isEmpty {
                    output += "  - \(desc)\n"
                }
                output += "  - ID: `\(project.id)`\n"
                output += "  - Frameworks: \(project.frameworks.joined(separator: ", "))\n"
            }
            output += "\n"
            return output
        }
    }
}
