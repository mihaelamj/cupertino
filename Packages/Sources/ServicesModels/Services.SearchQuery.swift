import Foundation
import SharedConstants

// MARK: - Services.SearchQuery

/// Common search query parameters for all docs / archive / evolution
/// / swift-org / swift-book searches that flow through
/// `Services.DocsSearchService` (and the unified search variants).
///
/// Previously declared inside
/// `Sources/Services/Services.SearchService.swift`. Lifted to the
/// foundation-layer `ServicesModels` target so callers
/// (`SearchToolProvider` / MCP / CLI / future test harnesses) can
/// construct queries without importing the full `Services` target.
extension Services {
    public struct SearchQuery: Sendable {
        public let text: String
        public let source: String?
        public let framework: String?
        public let language: String?
        public let limit: Int
        public let includeArchive: Bool
        public let minimumiOS: String?
        public let minimumMacOS: String?
        public let minimumTvOS: String?
        public let minimumWatchOS: String?
        public let minimumVisionOS: String?

        public init(
            text: String,
            source: String? = nil,
            framework: String? = nil,
            language: String? = nil,
            limit: Int = Shared.Constants.Limit.defaultSearchLimit,
            includeArchive: Bool = false,
            minimumiOS: String? = nil,
            minimumMacOS: String? = nil,
            minimumTvOS: String? = nil,
            minimumWatchOS: String? = nil,
            minimumVisionOS: String? = nil
        ) {
            self.text = text
            self.source = source
            self.framework = framework
            self.language = language
            self.limit = min(limit, Shared.Constants.Limit.maxSearchLimit)
            self.includeArchive = includeArchive
            self.minimumiOS = minimumiOS
            self.minimumMacOS = minimumMacOS
            self.minimumTvOS = minimumTvOS
            self.minimumWatchOS = minimumWatchOS
            self.minimumVisionOS = minimumVisionOS
        }
    }
}
