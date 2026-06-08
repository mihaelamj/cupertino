import Foundation
import SearchModels

// MARK: - Documents JSON Formatter

extension Services.Formatter.Documents {
    public struct JSON: Services.Formatter.Result {
        public init() {}

        public func format(_ page: Search.DocumentListPage) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            guard let data = try? encoder.encode(page),
                  let json = String(data: data, encoding: .utf8) else {
                return #"{"documents":[],"framework":"","limit":0,"offset":0,"source":"","total":0}"#
            }
            return json
        }
    }
}
