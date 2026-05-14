import ServicesModels
import Foundation

// MARK: - Footer Formattable Protocol

extension Services.Formatter.Footer {
    /// Protocol for formatting footer content
    public protocol Formattable {
        func format(_ items: [Item]) -> String
    }
}
