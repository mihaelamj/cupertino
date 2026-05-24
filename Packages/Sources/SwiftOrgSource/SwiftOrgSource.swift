import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftOrgSource

/// `Search.SourceProvider` conformer for the `swift-org` source.
/// Sixth per-source target of the #1007 epic. Mirrors AppleArchiveSource.
public struct SwiftOrgSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .search }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.SwiftOrgStrategy(
            swiftOrgDirectory: env.sourceDirectory,
            markdownStrategy: env.markdownStrategy,
            logger: env.logger
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.SwiftOrgIndexer()
    }
}
