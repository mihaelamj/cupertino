import Foundation
import Search
import SharedCore
import SearchModels

// MARK: - HIG JSON Formatter

extension Services.Formatter.HIG {
    /// Formats HIG search results as JSON for programmatic access
    public struct JSON: Services.Formatter.Result {
        private let query: Services.HIGQuery

        public init(query: Services.HIGQuery) {
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
}

// MARK: - HIG JSON Output Types (file-private)

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
