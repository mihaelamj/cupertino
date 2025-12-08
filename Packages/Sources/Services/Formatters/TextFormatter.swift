import Foundation
import Search
import Shared

// MARK: - Text Search Result Formatter

/// Formats search results as plain text for CLI output
public struct TextSearchResultFormatter: ResultFormatter {
    private let query: String
    private let config: SearchResultFormatConfig

    public init(query: String, config: SearchResultFormatConfig = .cliDefault) {
        self.query = query
        self.config = config
    }

    public func format(_ results: [Search.Result]) -> String {
        if results.isEmpty {
            return "No results found for '\(query)'"
        }

        var output = "Found \(results.count) result(s) for '\(query)':\n\n"

        for (index, result) in results.enumerated() {
            output += "[\(index + 1)] \(result.title)\n"
            output += "    Source: \(result.source) | Framework: \(result.framework)\n"
            output += "    URI: \(result.uri)\n"

            if !result.summary.isEmpty {
                output += "    \(result.summary)\n"
                if result.summaryTruncated {
                    output += "    ...\n"
                    let wordCount = result.summary.split(separator: " ").count
                    output += "    [truncated at ~\(wordCount) words] Full document: \(result.uri)\n"
                }
            }

            output += "\n"
        }

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

        return output
    }
}
