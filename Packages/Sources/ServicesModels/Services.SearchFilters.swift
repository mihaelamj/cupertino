import Foundation

// MARK: - Services.SearchFilters

/// Active filter set carried alongside a `Services.SearchQuery` for the
/// purpose of formatting search results. Formatters render banners or
/// chip strings based on which filters are non-nil.
///
/// Previously declared inside
/// `Sources/Services/Services.SearchService.swift`. Lifted to the
/// foundation-layer `ServicesModels` target alongside the query type.
extension Services {
    public struct SearchFilters: Sendable {
        public let source: String?
        public let framework: String?
        public let language: String?
        public let minimumiOS: String?
        public let minimumMacOS: String?
        public let minimumTvOS: String?
        public let minimumWatchOS: String?
        public let minimumVisionOS: String?

        public init(
            source: String? = nil,
            framework: String? = nil,
            language: String? = nil,
            minimumiOS: String? = nil,
            minimumMacOS: String? = nil,
            minimumTvOS: String? = nil,
            minimumWatchOS: String? = nil,
            minimumVisionOS: String? = nil
        ) {
            self.source = source
            self.framework = framework
            self.language = language
            self.minimumiOS = minimumiOS
            self.minimumMacOS = minimumMacOS
            self.minimumTvOS = minimumTvOS
            self.minimumWatchOS = minimumWatchOS
            self.minimumVisionOS = minimumVisionOS
        }

        /// Check if any filters are active
        public var hasActiveFilters: Bool {
            source != nil || framework != nil || language != nil ||
                minimumiOS != nil || minimumMacOS != nil || minimumTvOS != nil ||
                minimumWatchOS != nil || minimumVisionOS != nil
        }
    }
}
