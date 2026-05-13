import Foundation
import SharedConstants
import SharedCore
import SearchModels

// MARK: - Markdown Search Result Formatter

extension Services.Formatter {
    /// Formats search results as markdown for MCP tools and CLI --format markdown
    public struct Markdown: Result {
        private let query: String
        private let filters: Services.SearchFilters?
        private let config: Services.Formatter.Config
        private let teasers: Services.Formatter.TeaserResults?
        private let showPlatformTip: Bool

        public init(
            query: String,
            filters: Services.SearchFilters? = nil,
            config: Services.Formatter.Config = .mcpDefault,
            teasers: Services.Formatter.TeaserResults? = nil,
            showPlatformTip: Bool = true
        ) {
            self.query = query
            self.filters = filters
            self.config = config
            self.teasers = teasers
            self.showPlatformTip = showPlatformTip
        }

        public func format(_ results: [Search.Result]) -> String {
            var output = "# Search Results for \"\(query)\"\n\n"

            // Always tell the AI what source was searched
            let searchedSource = filters?.source ?? Shared.Constants.SourcePrefix.appleDocs
            output += "_Source: **\(searchedSource)**_\n\n"

            // Show other filters (not source since we just showed it)
            if let filters, filters.hasActiveFilters {
                if let framework = filters.framework {
                    output += "_Filtered to framework: **\(framework)**_\n\n"
                }
                if let language = filters.language {
                    output += "_Filtered to language: **\(language)**_\n\n"
                }
                if let minimumiOS = filters.minimumiOS {
                    output += "_Filtered to iOS: **\(minimumiOS)+**_\n\n"
                }
                if let minimumMacOS = filters.minimumMacOS {
                    output += "_Filtered to macOS: **\(minimumMacOS)+**_\n\n"
                }
                if let minimumTvOS = filters.minimumTvOS {
                    output += "_Filtered to tvOS: **\(minimumTvOS)+**_\n\n"
                }
                if let minimumWatchOS = filters.minimumWatchOS {
                    output += "_Filtered to watchOS: **\(minimumWatchOS)+**_\n\n"
                }
                if let minimumVisionOS = filters.minimumVisionOS {
                    output += "_Filtered to visionOS: **\(minimumVisionOS)+**_\n\n"
                }
            }

            output += "Found **\(results.count)** result\(results.count == 1 ? "" : "s"):\n\n"

            if results.isEmpty {
                output += config.emptyMessage
                output += "\n\n"
                output += Shared.Constants.Search.tipSearchCapabilities
                return output
            }

            for (index, result) in results.enumerated() {
                output += "## \(index + 1). \(result.title)\n\n"
                output += "- **Framework:** `\(result.framework)`\n"
                output += "- **URI:** `\(result.uri)`\n"

                if config.showAvailability,
                   let availability = result.availabilityString, !availability.isEmpty {
                    output += "- **Availability:** \(availability)\n"
                }
                if config.showScore {
                    output += "- **Score:** \(String(format: "%.2f", result.score))\n"
                }
                if config.showWordCount {
                    output += "- **Words:** \(result.wordCount)\n"
                }
                if config.showSource {
                    output += "- **Source:** \(result.source)\n"
                }
                // (#81) Show matched symbols from AST extraction
                if let symbols = result.matchedSymbols, !symbols.isEmpty {
                    let symbolStr = symbols.map { "`\($0.displayString)`" }.joined(separator: ", ")
                    output += "- **Symbols:** \(symbolStr)\n"
                }

                if !result.cleanedSummary.isEmpty {
                    output += "\n\(result.cleanedSummary)\n\n"
                } else {
                    output += "\n"
                }

                if config.showSeparators, index < results.count - 1 {
                    output += "---\n\n"
                }
            }

            // Footer: teasers, tips, and guidance
            let footer = Services.Formatter.Footer.Search.singleSource(
                searchedSource,
                teasers: teasers,
                showPlatformTip: showPlatformTip
            )
            output += footer.formatMarkdown()

            return output
        }
    }
}
