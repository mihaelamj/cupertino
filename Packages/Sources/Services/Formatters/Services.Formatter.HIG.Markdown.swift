import ServicesModels
import Foundation
import SearchModels
import SharedConstants
import SharedCore

// MARK: - HIG Markdown Formatter

extension Services.Formatter.HIG {
    /// Formats HIG search results as markdown
    public struct Markdown: Services.Formatter.Result {
        private let query: Services.HIGQuery
        private let config: Services.Formatter.Config
        private let teasers: Services.Formatter.TeaserResults?

        public init(
            query: Services.HIGQuery,
            config: Services.Formatter.Config = .mcpDefault,
            teasers: Services.Formatter.TeaserResults? = nil
        ) {
            self.query = query
            self.config = config
            self.teasers = teasers
        }

        public func format(_ results: [Search.Result]) -> String {
            var output = "# HIG Search Results for \"\(query.text)\"\n\n"

            // Tell the AI what source this is
            output += "_Source: **\(Shared.Constants.SourcePrefix.hig)**_\n\n"

            if let platform = query.platform {
                output += "_Platform: **\(platform)**_\n\n"
            }
            if let category = query.category {
                output += "_Category: **\(category)**_\n\n"
            }

            output += "Found **\(results.count)** guideline\(results.count == 1 ? "" : "s"):\n\n"

            if results.isEmpty {
                output += "_No Human Interface Guidelines found matching your query._\n\n"
                output += "**Tips:**\n"
                output += "- Try broader design terms (e.g., 'buttons', 'typography', 'navigation')\n"
                output += "- Specify a platform: iOS, macOS, watchOS, visionOS, tvOS\n"
                output += "- Specify a category: foundations, patterns, components, technologies, inputs\n\n"
                output += Shared.Constants.Search.tipSearchCapabilities
                return output
            }

            for (index, result) in results.enumerated() {
                output += "## \(index + 1). \(result.title)\n\n"
                output += "- **URI:** `\(result.uri)`\n"

                if config.showAvailability,
                   let availability = result.availabilityString, !availability.isEmpty {
                    output += "- **Availability:** \(availability)\n"
                }
                if config.showScore {
                    output += "- **Score:** \(String(format: "%.2f", result.score))\n"
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

            // Footer: tips and guidance
            let footer = Services.Formatter.Footer.Search.singleSource(
                Shared.Constants.SourcePrefix.hig,
                teasers: teasers
            )
            output += footer.formatMarkdown()

            return output
        }
    }
}
