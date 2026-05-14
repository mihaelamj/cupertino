import Foundation
import SearchModels
// MARK: - JSON Search Result Formatter

extension Services.Formatter {
    /// Formats search results as JSON for CLI --format json
    public struct JSON: Result {
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
}
