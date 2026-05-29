import AppleArchiveSource
import AppleDocsSource
import CoreSampleCode
import HIGSource
import PackagesSource
import SampleCodeSource
import SearchModels
import SharedConstants
import SwiftBookSource
import SwiftEvolutionSource
import SwiftOrgSource

// MARK: - Cupertino.CompositionRoot

//
// Single canonical declaration of the production source set. CLI's
// `cupertino serve` / `cupertino save` / `cupertino search` compose
// against `CupertinoComposition.makeProductionSourceRegistry()`;
// test targets that need the same registry shape (e.g. the MCP tool
// provider's route-map fixture, the per-source-fetcher tests) import
// CupertinoComposition and call the same factory.
//
// Adding a new source is one line below — the same edit that used to
// live inside CLIImpl.makeProductionSourceRegistry, but lifted into a
// foundation-of-the-app target so non-CLI consumers (tests, future
// MCP integrations, the bundle release tool) can iterate the same
// registry without depending on CLI.
//

public enum CupertinoComposition {
    /// Canonical production source registry. Every shipped
    /// `<X>Source` target is registered here exactly once; downstream
    /// consumers iterate `registry.allEnabled` to derive every
    /// registry-driven dispatch surface:
    ///
    /// - `Doctor.healthChecks` + `printSchemaVersions` per descriptor
    /// - `SaveSiblingGate.classifyPostSplitSourceID` via `destinationDB`
    /// - `Services.ReadService.resolveSource` via `destinationDB`
    /// - `CLIImpl.Command.Search.run` dispatch via `searchRoute`
    /// - MCP `CompositeToolProvider.handleSearch` dispatch via `searchRoute`
    /// - `cupertino setup` bundle-required descriptor list
    /// - `SearchToolProvider`'s source enum schema
    /// - `cupertino fetch` source list
    /// - `cupertino search`'s unified-search fan-out source list
    public static func makeProductionSourceRegistry() -> Search.SourceRegistry {
        var registry = Search.SourceRegistry()
        registry.register(AppleDocsSource())
        registry.register(HIGSource())
        registry.register(SampleCodeSource(fetcherFactory: Sample.Core.LiveGitHubFetcherFactory()))
        registry.register(AppleArchiveSource())
        registry.register(SwiftEvolutionSource())
        registry.register(SwiftOrgSource())
        registry.register(SwiftBookSource())
        registry.register(PackagesSource())
        return registry
    }

    /// Derived: source-id → `Search.SearchRoute` for the production
    /// registry. Equivalent to:
    ///
    ///     Dictionary(uniqueKeysWithValues: makeProductionSourceRegistry()
    ///         .allEnabled.map { ($0.definition.id, $0.searchRoute) })
    ///
    /// Surfaces the route map without re-iterating the registry at
    /// every consumer; tests + MCP composition root call it directly.
    public static func makeProductionSearchRoutesByID() -> [String: Search.SearchRoute] {
        Dictionary(
            uniqueKeysWithValues: makeProductionSourceRegistry().allEnabled.map { provider in
                (provider.definition.id, provider.searchRoute)
            }
        )
    }
}
