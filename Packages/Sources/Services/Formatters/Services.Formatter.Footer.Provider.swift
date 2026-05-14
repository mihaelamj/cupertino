import ServicesModels
import Foundation

// MARK: - Footer Provider Protocol

extension Services.Formatter.Footer {
    /// Protocol for types that can provide footer content
    public protocol Provider: Sendable {
        /// Generate footer items for this context
        func makeFooter() -> [Item]
    }
}
