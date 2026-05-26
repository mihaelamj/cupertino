import Foundation
import SearchModels
import SharedConstants

// MARK: - SwiftEvolutionSource

/// `Search.SourceProvider` conformer for the `swift-evolution` source.
/// Fifth per-source target of the #1007 epic. Mirrors the
/// AppleArchiveSource template post-#1014 (carries `destinationDB`).
public struct SwiftEvolutionSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition { Self.definition }

    public var fetchInfo: Search.FetchInfo? { Self.fetchInfo }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .swiftEvolution }

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

    /// #1045 Gap 3: every swift-evolution row is an evolution proposal.
    public func docKind(structuredKind _: String?, uriPath _: String) -> Search.DocKind { .evolutionProposal }
}
