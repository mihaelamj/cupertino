import Foundation
import Search
import Shared

// MARK: - HIG Text Formatter

/// Formats HIG search results as plain text for CLI output
public struct HIGTextFormatter: ResultFormatter {
    private let query: HIGQuery
    private let teasers: TeaserResults?

    public init(query: HIGQuery, teasers: TeaserResults? = nil) {
        self.query = query
        self.teasers = teasers
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
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.hig, teasers: teasers)
        output += footer.formatText()

        return output
    }
}

// MARK: - HIG JSON Formatter

/// Formats HIG search results as JSON for programmatic access
public struct HIGJSONFormatter: ResultFormatter {
    private let query: HIGQuery

    public init(query: HIGQuery) {
        self.query = query
    }

    public func format(_ results: [Search.Result]) -> String {
        let output = HIGJSONOutput(
            query: query.text,
            platform: query.platform,
            category: query.category,
            count: results.count,
            results: results.map(HIGResultOutput.init)
        )

        return encodeJSON(output)
    }
}

// MARK: - HIG JSON Output Types

private struct HIGJSONOutput: Encodable {
    let query: String
    let platform: String?
    let category: String?
    let count: Int
    let results: [HIGResultOutput]
}

private struct HIGResultOutput: Encodable {
    let title: String
    let uri: String
    let availability: String?
    let summary: String

    init(from result: Search.Result) {
        title = result.title
        uri = result.uri
        availability = result.availabilityString
        summary = result.cleanedSummary
    }
}

// MARK: - JSON Encoding Helper

private func encodeJSON(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? encoder.encode(value),
          let json = String(data: data, encoding: .utf8)
    else {
        return "{\"error\": \"Failed to encode results\"}"
    }

    return json
}
