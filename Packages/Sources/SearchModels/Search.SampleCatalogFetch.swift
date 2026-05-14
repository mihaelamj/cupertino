import Foundation
import SharedConstants

// MARK: - Search.SampleCatalogFetch

/// Closure shape that returns the current state of the Apple sample-code
/// catalog. The Search target's `SampleCodeStrategy` uses one of these
/// instead of reaching into `CoreSampleCode` directly — that's how the
/// strategy can index the sample catalog while the Search SPM target
/// keeps a foundation-only dependency graph.
///
/// The composition root (the CLI binary) supplies the concrete closure
/// which adapts from `Sample.Core.Catalog`'s static API into the
/// `SampleCatalogState` shape declared below. Test harnesses pass a
/// closure that returns a fixture state directly.
///
/// Mirrors the `Search.Database` / `Search.MarkdownToStructuredPage` /
/// `MakeSearchDatabase` / `PackageFileLookup` / `MarkdownLookup`
/// closure-typealias pattern already in SearchModels: the abstraction
/// lives in this value-types target, the implementation lives in the
/// producer target, the wiring lives at the composition root.
public extension Search {
    typealias SampleCatalogFetch = @Sendable () async -> SampleCatalogState
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
/// field-for-field when building the `SampleCatalogFetch` closure;
/// the round-trip is lossless because both types carry the same six
/// fields.
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
