import Foundation

// MARK: - Search.PackageFetchStrategyFactory

extension Search {
    /// GoF Abstract Factory (1994 p. 87) seam for the Swift Package
    /// Index fetch strategy. The concrete `PackagesFetchStrategy` and its
    /// 3-stage pipeline (SPI metadata refresh, GitHub archive download,
    /// availability annotation) live in the `CorePackageIndexing`
    /// producer next to the machinery (`PackageFetcher`,
    /// `PackageDependencyResolver`, `PackageArchiveExtractor`,
    /// `PackageAvailabilityAnnotator`) it drives.
    ///
    /// `PackagesSource` is a foundation-only producer (a STRICT_PRODUCER),
    /// so it must not import the concrete `CorePackageIndexing` producer.
    /// It depends only on this seam and receives the factory by init
    /// injection from the composition root (#536 lift 5).
    ///
    /// Returns `any Search.SourceFetchStrategy`, so the protocol lives in
    /// `SearchModels` rather than `CorePackageIndexingModels`.
    public protocol PackageFetchStrategyFactory: Sendable {
        /// Build the Swift Package Index fetch strategy.
        func makeStrategy() -> any Search.SourceFetchStrategy
    }
}
