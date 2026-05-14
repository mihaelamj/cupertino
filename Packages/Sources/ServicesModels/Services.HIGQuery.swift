import Foundation
import SharedConstants

// MARK: - Services.HIGQuery

/// Query parameters for HIG (Human Interface Guidelines) searches that
/// flow through `Services.HIGSearchService`.
///
/// Previously declared inside
/// `Sources/Services/ReadCommands/Services.HIGSearchService.swift`.
/// Lifted to the foundation-layer `ServicesModels` target so callers
/// (`SearchToolProvider` / MCP / CLI) can construct HIG queries
/// without importing the full `Services` target.
extension Services {
    public struct HIGQuery: Sendable {
        public let text: String
        /// iOS, macOS, watchOS, visionOS, tvOS.
        public let platform: String?
        /// foundations, patterns, components, technologies, inputs.
        public let category: String?
        public let limit: Int

        public init(
            text: String,
            platform: String? = nil,
            category: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit
        ) {
            self.text = text
            self.platform = platform
            self.category = category
            self.limit = min(limit, Shared.Constants.Limit.maxSearchLimit)
        }
    }
}
