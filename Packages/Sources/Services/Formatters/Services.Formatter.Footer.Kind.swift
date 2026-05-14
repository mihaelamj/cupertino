import ServicesModels
import Foundation

// MARK: - Footer Kind

extension Services.Formatter.Footer {
    /// Types of footer content in search results
    public enum Kind: String, Sendable, CaseIterable {
        case sourceTip // Tip about other sources
        case semanticTip // Tip about semantic search tools
        case teaser // Preview results from other sources
        case platformTip // Tip about platform filters
        case custom // Custom footer content
    }
}
