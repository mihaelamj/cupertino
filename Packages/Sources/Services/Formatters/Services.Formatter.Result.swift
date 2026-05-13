import Foundation
import SharedCore
import SearchModels

// MARK: - Result Formatter Protocol

extension Services.Formatter {
    /// Protocol for formatting search results to different output formats
    public protocol Result {
        associatedtype Input
        func format(_ input: Input) -> String
    }
}
