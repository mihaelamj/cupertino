import Foundation

// MARK: - Footer Kind

extension Services.Formatter.Footer {
    /// Types of footer content in search results
    public enum Kind: String, Sendable, CaseIterable {
        case sourceTip // Tip about other sources (actionable, top of footer)
        case semanticTip // Tip about semantic search tools
        case teaser // Preview results from other sources
        case platformTip // Tip about platform filters
        case allSourcesDiscovery // Bottom-of-footer "all registered sources" block — discovery, always present (#1045 Gap 2)
        case custom // Custom footer content
    }
}
