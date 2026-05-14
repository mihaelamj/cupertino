import Foundation
import SearchModels
import SharedConstants
// MARK: - Text Search Result Formatter

extension Services.Formatter {
    /// Formats search results as plain text for CLI output
    public struct Text: Result {
        private let query: String
        private let source: String?
        private let config: Services.Formatter.Config
        private let teasers: TeaserResults?

        public init(
            query: String,
            source: String? = nil,
            config: Services.Formatter.Config = .cliDefault,
            teasers: TeaserResults? = nil
        ) {
            self.query = query
            self.source = source
            self.config = config
            self.teasers = teasers
        }

        public func format(_ results: [Search.Result]) -> String {
            if results.isEmpty {
                return "No results found for '\(query)'"
            }

            var output = "Found \(results.count) result(s) for '\(query)':\n\n"

            for (index, result) in results.enumerated() {
                output += "[\(index + 1)] \(result.title)\n"

                // Build metadata line respecting config
                var metadata: [String] = []
                if config.showSource {
                    metadata.append("Source: \(result.source)")
                }
                metadata.append("Framework: \(result.framework)")
                if config.showScore {
                    metadata.append("Score: \(String(format: "%.2f", result.score))")
                }
                if config.showWordCount {
                    metadata.append("Words: \(result.wordCount)")
                }
                output += "    \(metadata.joined(separator: " | "))\n"

                output += "    URI: \(result.uri)\n"

                if config.showAvailability,
                   let availability = result.availabilityString, !availability.isEmpty {
                    output += "    Availability: \(availability)\n"
                }
                // (#81) Show matched symbols from AST extraction
                if let symbols = result.matchedSymbols, !symbols.isEmpty {
                    let symbolStr = symbols.map(\.displayString).joined(separator: ", ")
                    output += "    Symbols: \(symbolStr)\n"
                }

                if !result.cleanedSummary.isEmpty {
                    output += "    \(result.cleanedSummary)\n"
                    if result.summaryTruncated {
                        output += "    ...\n"
                        let wordCount = result.cleanedSummary.split(separator: " ").count
                        output += "    [truncated at ~\(wordCount) words] Full document: \(result.uri)\n"
                    }
                }

                output += "\n"
            }

            // Footer: teasers, tips, and guidance
            let searchedSource = source ?? Shared.Constants.SourcePrefix.appleDocs
            let footer = Services.Formatter.Footer.Search.singleSource(searchedSource, teasers: teasers)
            output += footer.formatText()

            return output
        }
    }
}
