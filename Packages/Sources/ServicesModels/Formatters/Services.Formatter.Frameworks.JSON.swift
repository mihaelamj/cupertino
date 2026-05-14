import Foundation
// MARK: - Frameworks JSON Formatter

extension Services.Formatter.Frameworks {
    /// Formats framework list as JSON
    public struct JSON: Services.Formatter.Result {
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
}
