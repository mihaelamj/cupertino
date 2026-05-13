import Foundation

// MARK: - Search Result Format Configuration

extension Services.Formatter {
    /// Configuration for search result formatting
    public struct Config: Sendable {
        public let showScore: Bool
        public let showWordCount: Bool
        public let showSource: Bool
        public let showAvailability: Bool
        public let showSeparators: Bool
        public let emptyMessage: String

        public init(
            showScore: Bool = false,
            showWordCount: Bool = false,
            showSource: Bool = true,
            showAvailability: Bool = false,
            showSeparators: Bool = false,
            emptyMessage: String = "No results found"
        ) {
            self.showScore = showScore
            self.showWordCount = showWordCount
            self.showSource = showSource
            self.showAvailability = showAvailability
            self.showSeparators = showSeparators
            self.emptyMessage = emptyMessage
        }

        /// Shared configuration for both CLI and MCP markdown output (identical results)
        public static let shared = Config(
            showScore: true,
            showWordCount: true,
            showSource: false,
            showAvailability: true,
            showSeparators: true,
            emptyMessage: "_No results found. Try broader search terms._"
        )

        /// Alias for CLI (uses shared config for identical output)
        public static let cliDefault = shared

        /// Alias for MCP (uses shared config for identical output)
        public static let mcpDefault = shared
    }
}
