import Foundation
import SearchModels

// MARK: - LivePackageFetchStrategyFactory

/// Production `Search.PackageFetchStrategyFactory`. Lives in the
/// `CorePackageIndexing` producer next to the `PackagesFetchStrategy` it
/// builds. The composition root instantiates it and injects it into the
/// `PackagesSource` provider, which depends only on the
/// `Search.PackageFetchStrategyFactory` seam (#536 lift 5).
public struct LivePackageFetchStrategyFactory: Search.PackageFetchStrategyFactory {
    public init() {}

    public func makeStrategy() -> any Search.SourceFetchStrategy {
        PackagesFetchStrategy()
    }
}
