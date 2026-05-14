import Foundation
import SharedConstants

// MARK: - Search.SampleCatalogProvider

/// Provider of the current sample-code catalog state for the Search
/// indexer. GoF Strategy pattern (Gamma et al, 1994): a family of
/// algorithms (load from on-disk JSON, embedded fallback, test
/// fixture) interchangeable behind a named protocol.
///
/// The Search target's `SampleCodeStrategy` accepts a conformer at
/// init so it can index the catalog without reaching into
/// `CoreSampleCode` directly. The composition root (the CLI binary)
/// supplies a concrete conformer that adapts from `Sample.Core.Catalog`'s
/// static API into the `SampleCatalogState` shape declared below.
/// Test harnesses pass a struct that returns a fixture state directly.
///
/// This replaces the previous
/// `Search.SampleCatalogFetch = @Sendable () async -> SampleCatalogState`
/// closure typealias. The protocol form names the contract at the
/// constructor site (`sampleCatalogProvider:`), makes captured-state
/// surface explicit on the conforming type's stored properties, and
/// produces one-line test mocks instead of inline async closures.
public extension Search {
    protocol SampleCatalogProvider: Sendable {
        /// Return the catalog state at the moment of call. The
        /// concrete provider decides whether to read on-disk JSON,
        /// hit an embedded fallback, or return a fixture; the Search
        /// strategy doesn't care.
        func fetch() async -> SampleCatalogState
    }
}

// MARK: - Search.SampleCatalogState

/// Snapshot of what's available in the sample-code catalog at the
/// moment the indexer runs.
public extension Search {
    enum SampleCatalogState: Sendable {
        /// The catalog was loaded successfully (either from the on-disk
        /// JSON or from an embedded fallback). Entries may still be
        /// empty if the catalog file existed but parsed to zero rows.
        case loaded(entries: [SampleCatalogEntry])

        /// The catalog file was not found. The associated path is the
        /// fully-resolved on-disk location the indexer is reporting in
        /// the "run `cupertino fetch --type code` to populate" message.
        case missing(onDiskPath: String)
    }
}

// MARK: - Search.SampleCatalogEntry

/// One row from the sample-code catalog, mirroring `Sample.Core.Entry`'s
/// shape. Lives in SearchModels (a foundation-only target) so the
/// strategy that consumes the catalog can be typed against the snapshot
/// without importing the CoreSampleCode target where the concrete
/// `Sample.Core.Entry` lives.
///
/// The composition root maps `Sample.Core.Entry` → this struct
/// field-for-field when building the catalog provider; the round-trip
/// is lossless because both types carry the same six fields.
public extension Search {
    struct SampleCatalogEntry: Sendable {
        public let title: String
        public let url: String
        public let framework: String
        public let description: String
        public let zipFilename: String
        public let webURL: String

        public init(
            title: String,
            url: String,
            framework: String,
            description: String,
            zipFilename: String,
            webURL: String
        ) {
            self.title = title
            self.url = url
            self.framework = framework
            self.description = description
            self.zipFilename = zipFilename
            self.webURL = webURL
        }
    }
}
