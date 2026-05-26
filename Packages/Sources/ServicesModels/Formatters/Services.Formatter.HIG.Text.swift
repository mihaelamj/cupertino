import Foundation
import SearchModels
import SharedConstants

// MARK: - HIG Text Formatter

extension Services.Formatter.HIG {
    /// Formats HIG search results as plain text for CLI output
    public struct Text: Services.Formatter.Result {
        private let query: Services.HIGQuery
        private let teasers: Services.Formatter.TeaserResults?
        /// #1045 Gap 2: registry-derived source-id list for the
        /// footer's "narrow with --source: …" tip. nil falls back to
        /// the foundation-tier static; composition root supplies the
        /// list from `makeProductionSourceRegistry().allEnabled.map(\.definition.id)`.
        private let availableSources: [String]

        public init(
            query: Services.HIGQuery,
            teasers: Services.Formatter.TeaserResults? = nil,
            availableSources: [String]
        ) {
            self.query = query
            self.teasers = teasers
            self.availableSources = availableSources
        }

        public func format(_ results: [Search.Result]) -> String {
            var output = "HIG Search Results for \"\(query.text)\"\n"
            output += String(repeating: "=", count: 50) + "\n\n"

            if let platform = query.platform {
                output += "Platform: \(platform)\n"
            }
            if let category = query.category {
                output += "Category: \(category)\n"
            }
            if query.platform != nil || query.category != nil {
                output += "\n"
            }

            output += "Found \(results.count) guideline(s)\n\n"

            if results.isEmpty {
                output += "No Human Interface Guidelines found matching your query.\n\n"
                output += "Tips:\n"
                output += "- Try broader design terms (e.g., 'buttons', 'typography', 'navigation')\n"
                output += "- Specify a platform: iOS, macOS, watchOS, visionOS, tvOS\n"
                output += "- Specify a category: foundations, patterns, components, technologies, inputs\n"
                return output
            }

            for (index, result) in results.enumerated() {
                output += "\(index + 1). \(result.title)\n"
                output += "   URI: \(result.uri)\n"
                if let availability = result.availabilityString, !availability.isEmpty {
                    output += "   Availability: \(availability)\n"
                }
                if !result.cleanedSummary.isEmpty {
                    output += "\n   \(result.cleanedSummary)\n\n"
                } else {
                    output += "\n"
                }
            }

            // Footer: teasers, tips, and guidance
            let footer = Services.Formatter.Footer.Search.singleSource(
                Shared.Constants.SourcePrefix.hig,
                teasers: teasers,
                availableSources: availableSources
            )
            output += footer.formatText()

            return output
        }
    }
}
