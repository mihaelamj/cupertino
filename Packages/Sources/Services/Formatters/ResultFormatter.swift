import Foundation
import Search
import Shared

// MARK: - Result Formatter Protocol

/// Protocol for formatting search results to different output formats
public protocol ResultFormatter {
    associatedtype Input
    func format(_ input: Input) -> String
}

// MARK: - Search Result Format Configuration

/// Configuration for search result formatting
public struct SearchResultFormatConfig: Sendable {
    public let showScore: Bool
    public let showWordCount: Bool
    public let showSource: Bool
    public let showSeparators: Bool
    public let emptyMessage: String

    public init(
        showScore: Bool = false,
        showWordCount: Bool = false,
        showSource: Bool = true,
        showSeparators: Bool = false,
        emptyMessage: String = "No results found"
    ) {
        self.showScore = showScore
        self.showWordCount = showWordCount
        self.showSource = showSource
        self.showSeparators = showSeparators
        self.emptyMessage = emptyMessage
    }

    /// Default configuration for CLI output
    public static let cliDefault = SearchResultFormatConfig(
        showScore: false,
        showWordCount: false,
        showSource: true,
        showSeparators: false,
        emptyMessage: "No results found"
    )

    /// Default configuration for MCP tool output
    public static let mcpDefault = SearchResultFormatConfig(
        showScore: true,
        showWordCount: true,
        showSource: false,
        showSeparators: true,
        emptyMessage: "_No results found. Try broader search terms._"
    )
}
