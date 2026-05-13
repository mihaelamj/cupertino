import Foundation
import SharedConstants

// MARK: - Shared.Configuration.Output.Format

extension Shared.Configuration.Output {
    public enum Format: String, Codable, Sendable {
        /// Primary output is JSON (StructuredDocumentationPage)
        case json
        /// Primary output is markdown
        case markdown
        /// Primary output is HTML
        case html
    }
}
