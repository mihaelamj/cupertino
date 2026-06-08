import Foundation
import SearchModels

// MARK: - Document Children JSON Formatter

extension Services.Formatter.DocumentChildren {
    public struct JSON: Services.Formatter.Result {
        public init() {}

        public func format(_ page: Search.DocumentChildrenPage) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            guard let data = try? encoder.encode(page),
                  let json = String(data: data, encoding: .utf8) else {
                return #"{"children":[],"parentURI":"","source":""}"#
            }
            return json
        }
    }
}
