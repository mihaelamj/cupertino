import Foundation
import Search
import Shared

// MARK: - JSON Search Result Formatter

/// Formats search results as JSON for CLI --format json
public struct JSONSearchResultFormatter: ResultFormatter {
    public init() {}

    public func format(_ results: [Search.Result]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(results),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}

// MARK: - Frameworks JSON Formatter

/// Formats framework list as JSON
public struct FrameworksJSONFormatter: ResultFormatter {
    public init() {}

    public func format(_ frameworks: [String: Int]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Convert to array of objects for better readability
        let frameworkList = frameworks.map { FrameworkEntry(name: $0.key, documentCount: $0.value) }
            .sorted { $0.documentCount > $1.documentCount }

        guard let data = try? encoder.encode(frameworkList),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private struct FrameworkEntry: Encodable {
        let name: String
        let documentCount: Int
    }
}
