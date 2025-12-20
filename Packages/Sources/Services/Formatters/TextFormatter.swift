import Foundation
import Search
import Shared

// MARK: - Text Search Result Formatter

/// Formats search results as plain text for CLI output
public struct TextSearchResultFormatter: ResultFormatter {
    private let query: String
    private let source: String?
    private let config: SearchResultFormatConfig
    private let teasers: TeaserResults?

    public init(
        query: String,
        source: String? = nil,
        config: SearchResultFormatConfig = .cliDefault,
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
        let footer = SearchFooter.singleSource(searchedSource, teasers: teasers)
        output += footer.formatText()

        return output
    }
}

// MARK: - Frameworks Text Formatter

/// Formats framework list as plain text for CLI output
public struct FrameworksTextFormatter: ResultFormatter {
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
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.appleDocs)
        output += footer.formatText()

        return output
    }
}
