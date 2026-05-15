import Foundation

// MARK: - Shared.Configuration.Output

extension Shared.Configuration {
    /// Configuration for output format
    public struct Output: Codable, Sendable {
        public let format: Format
        public let includeMarkdown: Bool

        public init(
            format: Format = .json,
            includeMarkdown: Bool = false
        ) {
            self.format = format
            self.includeMarkdown = includeMarkdown
        }
    }
}
