import Foundation
import SharedConstants

// MARK: - Search.IndexDocumentParams

extension Search {
    /// Parameter bundle for `Search.IndexWriter.indexDocument(_:)` and
    /// the concrete `Search.Index.indexDocument(_:)` actor method that
    /// conforms it.
    ///
    /// The underlying indexer originally accepted 18 parameters, most
    /// with defaults, several added incrementally as the indexer learned
    /// new sources (`minIOS` / `minMacOS` / `minTvOS` / `minWatchOS` /
    /// `minVisionOS`) and new database layouts (`packageId`, `jsonData`,
    /// `availabilitySource`). 18-arg call sites were unreadable and any
    /// new field meant re-touching every caller. `IndexDocumentParams`
    /// groups the fields so call sites can name only what's specific to
    /// the page; defaults flow through.
    ///
    /// Lifted from the previous nested location inside the `Search.Index`
    /// actor in the Search target up to top-level `Search.IndexDocumentParams`
    /// here in `SearchModels` by epic #893's child #896, so the new
    /// `Search.IndexWriter` protocol seam can name the parameter type
    /// without taking a behavioural dependency on the concrete Search
    /// target.
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
