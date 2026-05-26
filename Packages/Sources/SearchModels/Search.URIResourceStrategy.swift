import Foundation
import LoggingModels
import SharedConstants

// MARK: - Search.URIResourceStrategy

extension Search {
    /// Per-source MCP-resource probing strategy. Each source whose data
    /// is reachable via an MCP `resources/{list,read}` URI scheme
    /// supplies one of these via
    /// `Search.SourceProvider.makeURIResourceStrategy()`.
    ///
    /// 2026-05-26 audit Cluster 12 follow-up. Pre-fix the
    /// `MCP.Support.DocsResourceProvider.readResource` dispatch had 3
    /// hardcoded `if uri.hasPrefix(...)` arms (apple-docs / swift-evolution
    /// / apple-archive), each carrying 30-50 LOC of bespoke URI parsing
    /// + filesystem probing + (apple-docs only) JSON-vs-md decode logic.
    /// Adding a new docs-tier source whose pages reach the client via
    /// `resources/read` required editing the if/else chain AND adding a
    /// new parse helper. Post-fix the dispatch iterates the registry of
    /// strategies; each strategy owns its scheme + parsing + probing.
    ///
    /// `listResources` follows the same shape: the strategy returns the
    /// `URIResource` entries (with stable URI, name, description) that
    /// belong in its slice of the MCP resource list. Apple-docs reads
    /// from `CrawlMetadata.pages` (the framework-root filter on the
    /// `apple-docs://` URI shape); swift-evolution + apple-archive
    /// enumerate the on-disk corpus directly.
    ///
    /// Per `gof-di-rules.md` Rule 3 the protocol lives in this
    /// foundation tier; per Rule 4 strategies are `any`-erased
    /// concretes, not closure typealiases.
    public protocol URIResourceStrategy: Sendable {
        /// The URI scheme this strategy recognises, e.g.
        /// `"apple-docs://"`. The dispatcher uses `uri.hasPrefix(scheme)`
        /// to select the matching strategy.
        var scheme: String { get }

        /// Build the `URIResource` entries this source contributes to
        /// the MCP `resources/list` page. Apple-docs filters
        /// `env.metadata.pages` to framework-root URIs; swift-evolution
        /// + apple-archive enumerate `env.sourceDirectory` for `.md`
        /// files matching their on-disk shape.
        ///
        /// Returns an empty array if the corpus is absent; errors
        /// rethrow so the dispatcher can log + skip (other sources'
        /// slices still build).
        func listResources(env: URIResourceEnvironment) async throws -> [URIResource]

        /// Read the markdown content for `uri` from this source's
        /// on-disk corpus. Returns `nil` if the URI's scheme matches
        /// but the resource isn't found (so the dispatcher can throw
        /// `notFound(uri)` with the original URI). Throws on actual
        /// I/O or parse errors.
        func readMarkdown(uri: String, env: URIResourceEnvironment) async throws -> String?
    }

    /// Shared environment threaded through each strategy at runtime.
    /// The composition root in `CLIImpl.Command.Serve` builds one
    /// instance per source by resolving `provider.fetchInfo.defaultOutputDirKey`
    /// to a URL and passing the parsed `CrawlMetadata` (apple-docs
    /// only; nil for the other sources).
    public struct URIResourceEnvironment: Sendable {
        /// On-disk corpus directory for this source. Resolved by the
        /// composition root from
        /// `Shared.Paths.directory(named: provider.fetchInfo!.defaultOutputDirKey.rawValue)`
        /// with the same `--docs-dir` / `--evolution-dir` CLI override
        /// precedence Doctor uses.
        public let sourceDirectory: URL

        /// Apple-docs-specific: parsed crawl metadata used by the
        /// framework-root URI filter in `listResources`. Nil for every
        /// other source.
        public let metadata: Shared.Models.CrawlMetadata?

        /// Stable input for diagnostic logging (e.g.
        /// `DocsResourceProvider: apple-docs slice unavailable (...)`).
        public let logger: any LoggingModels.Logging.Recording

        public init(
            sourceDirectory: URL,
            metadata: Shared.Models.CrawlMetadata? = nil,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.sourceDirectory = sourceDirectory
            self.metadata = metadata
            self.logger = logger
        }
    }

    /// One entry in the MCP `resources/list` slice this strategy
    /// contributes. Mirrors `MCP.Core.Protocols.Resource` but stays in
    /// the foundation tier so per-source strategies don't import
    /// MCP.Core. The dispatcher in `MCP.Support.DocsResourceProvider`
    /// maps these to `Protocols.Resource` at the boundary.
    public struct URIResource: Sendable {
        public let uri: String
        public let name: String
        public let description: String

        public init(uri: String, name: String, description: String) {
            self.uri = uri
            self.name = name
            self.description = description
        }
    }
}

// MARK: - SourceProvider default

extension Search.SourceProvider {
    /// Default: this source has no MCP-resource URI scheme. Sources
    /// whose pages reach the client via `resources/read` override and
    /// return their strategy concrete. Today: AppleDocsSource (apple-docs
    /// scheme), SwiftEvolutionSource (swift-evolution scheme),
    /// AppleArchiveSource (apple-archive scheme).
    public func makeURIResourceStrategy() -> (any Search.URIResourceStrategy)? { nil }
}
