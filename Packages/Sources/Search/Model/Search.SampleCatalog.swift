import Foundation
import SharedConstants

// MARK: - Search.SampleCatalog.Provider

/// Sub-namespace grouping the SampleCatalog-related types (Provider +
/// State + Entry). Post-#1042 type-name deepening; back-compat
/// typealiases preserve the pre-rename flat names.
extension Search {
    public enum SampleCatalog {}
}

/// Provider of the current sample-code catalog state for the Search
/// indexer. GoF Strategy pattern (Gamma et al, 1994).
///
/// The SearchAPI target's `SampleCodeStrategy` accepts a conformer at
/// init so it can index the catalog without reaching into
/// `CoreSampleCode` directly. The composition root (the CLI binary)
/// supplies a concrete conformer that adapts from `Sample.Core.Catalog`'s
/// static API into the `State` shape declared below. Test harnesses
/// pass a struct that returns a fixture state directly.
extension Search.SampleCatalog {
    public protocol Provider: Sendable {
        /// Return the catalog state at the moment of call. The
        /// concrete provider decides whether to read on-disk JSON,
        /// hit an embedded fallback, or return a fixture; the Search
        /// strategy doesn't care.
        func fetch() async -> State
    }

    /// Snapshot of what's available in the sample-code catalog at the
    /// moment the indexer runs.
    public enum State: Sendable {
        /// The catalog was loaded successfully (either from the on-disk
        /// JSON or from an embedded fallback). Entries may still be
        /// empty if the catalog file existed but parsed to zero rows.
        case loaded(entries: [Entry])

        /// The catalog file was not found. The associated path is the
        /// fully-resolved on-disk location the indexer is reporting in
        /// the "run `cupertino fetch --source apple-sample-code` to populate" message.
        case missing(onDiskPath: String)
    }

    /// One row from the sample-code catalog, mirroring `Sample.Core.Entry`'s
    /// shape. Lives in SearchModels (a foundation-only target) so the
    /// strategy that consumes the catalog can be typed against the snapshot
    /// without importing the CoreSampleCode target where the concrete
    /// `Sample.Core.Entry` lives.
    public struct Entry: Sendable {
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

/// Back-compat aliases for pre-#1042 consumers.
extension Search {
    public typealias SampleCatalogProvider = SampleCatalog.Provider
    public typealias SampleCatalogState = SampleCatalog.State
    public typealias SampleCatalogEntry = SampleCatalog.Entry
}
