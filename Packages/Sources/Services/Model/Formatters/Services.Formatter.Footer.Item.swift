import Foundation

// MARK: - Footer Item

extension Services.Formatter.Footer {
    /// A single footer item
    public struct Item: Sendable {
        public let kind: Kind
        public let title: String?
        public let content: String
        public let emoji: String?

        public init(
            kind: Kind,
            title: String? = nil,
            content: String,
            emoji: String? = nil
        ) {
            self.kind = kind
            self.title = title
            self.content = content
            self.emoji = emoji
        }
    }
}
