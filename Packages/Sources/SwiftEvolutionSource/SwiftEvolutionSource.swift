import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftEvolutionSource

/// `Search.SourceProvider` conformer for the `swift-evolution` source.
/// Fifth per-source target of the #1007 epic. Mirrors the
/// AppleArchiveSource template post-#1014 (carries `destinationDB`).
public struct SwiftEvolutionSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition {
        Self.definition
    }

    public var fetchInfo: Search.FetchInfo? {
        Self.fetchInfo
    }

    public var destinationDB: Shared.Models.DatabaseDescriptor {
        .swiftEvolution
    }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text],
            operations: [.readByURI],
            metadata: [
                .hasMinSwiftVersion: true,
                .hasProposalNumber: true,
            ]
        )
    }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        Search.SwiftEvolutionStrategy(
            evolutionDirectory: env.sourceDirectory,
            logger: env.logger
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        Search.SwiftEvolutionIndexer()
    }

    /// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy.
    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        SwiftEvolutionFetchStrategy()
    }

    /// 2026-05-26 audit #1055: per-source read strategy. Shared
    /// `Search.DocsReadStrategy` resolves to this source's per-source
    /// DB via `env.docsDBURLs[sourceID]`.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        Search.DocsReadStrategy(sourceID: definition.id)
    }
}
