import Foundation
import SearchModels
import SharedConstants

// MARK: - Search.Index.IndexDocumentParams

extension Search.Index {
    /// Parameter bundle for `Search.Index.indexDocument(_:)`.
    ///
    /// The original signature accepted 18 parameters — most of them with
    /// defaults, several added incrementally as the indexer learned new
    /// sources (`minIOS` / `minMacOS` / …) and new database layouts
    /// (`packageId`, `jsonData`, `availabilitySource`). 18-arg call sites
    /// were unreadable and any new field meant re-touching every caller.
    ///
    /// `IndexDocumentParams` groups the fields so call sites can name
    /// only what's specific to the page; defaults flow through.
    public struct IndexDocumentParams: Sendable {
        public let uri: String
        public let source: String
        public let framework: String?
        public let language: String?
        public let title: String
        public let content: String
        public let filePath: String
        public let contentHash: String
        public let lastCrawled: Date
        public let sourceType: String
        public let packageId: Int?
        public let jsonData: String?
        public let minIOS: String?
        public let minMacOS: String?
        public let minTvOS: String?
        public let minWatchOS: String?
        public let minVisionOS: String?
        public let availabilitySource: String?

        public init(
            uri: String,
            source: String,
            framework: String?,
            language: String? = nil,
            title: String,
            content: String,
            filePath: String,
            contentHash: String,
            lastCrawled: Date,
            sourceType: String = Shared.Constants.Database.defaultSourceTypeApple,
            packageId: Int? = nil,
            jsonData: String? = nil,
            minIOS: String? = nil,
            minMacOS: String? = nil,
            minTvOS: String? = nil,
            minWatchOS: String? = nil,
            minVisionOS: String? = nil,
            availabilitySource: String? = nil
        ) {
            self.uri = uri
            self.source = source
            self.framework = framework
            self.language = language
            self.title = title
            self.content = content
            self.filePath = filePath
            self.contentHash = contentHash
            self.lastCrawled = lastCrawled
            self.sourceType = sourceType
            self.packageId = packageId
            self.jsonData = jsonData
            self.minIOS = minIOS
            self.minMacOS = minMacOS
            self.minTvOS = minTvOS
            self.minWatchOS = minWatchOS
            self.minVisionOS = minVisionOS
            self.availabilitySource = availabilitySource
        }
    }
}
