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

    /// Post #1038: swift-org gets its own dedicated DB
    /// (`swift-org.db`) rather than the pre-#1038 view-source
    /// co-location in `swift-documentation.db` with swift-book.
    /// Per-page emission filtering lives in
    /// `Search.SwiftOrgStrategy.indexItems` which calls the shared
    /// `Search.StrategyHelpers.crawlSwiftDocumentation` helper with
    /// `scope: .swiftOrgOnly`.
    public var destinationDB: Shared.Models.DatabaseDescriptor { .swiftOrg }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text, .symbols, .generics],
            operations: [.readByURI],
            metadata: [
                .hasGenerics: true,
                .hasAvailabilityAttrs: true,
            ]
        )
    }

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

    /// #1045 Gap 3: every swift-org row classifies as `.swiftOrgDoc`.
    public func docKind(structuredKind _: String?, uriPath _: String) -> Search.DocKind { .swiftOrgDoc }
}
