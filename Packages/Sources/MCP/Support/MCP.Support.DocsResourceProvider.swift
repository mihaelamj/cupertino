import Foundation
import LoggingModels
import MCPCore
import MCPSharedTools
import SearchModels
import SharedConstants

// MARK: - Documentation Resource Provider

extension MCP.Support {
    /// Strategy for resolving a resource URI to pre-rendered markdown
    /// out of a search-index database (or any other source). GoF
    /// Strategy pattern: returns `nil` if the URI is not present;
    /// throws if the lookup itself fails. `DocsResourceProvider`
    /// treats either as a fall-back trigger to read from the
    /// filesystem.
    ///
    /// Replaces the previous
    /// `MarkdownLookup = @Sendable (String) async throws -> String?`
    /// closure typealias. Conforming types name the contract, make
    /// captured state explicit, and produce one-line test mocks
    /// instead of inline closures.
    public protocol MarkdownLookupStrategy: Sendable {
        func lookup(uri: String) async throws -> String?
    }

    /// Provides crawled documentation as MCP resources.
    ///
    /// The provider's database lookup is injected as a
    /// `MarkdownLookupStrategy` conformer rather than a concrete
    /// `Search.Index` value, so this target stays free of any
    /// behavioural dependency on Search. Consumers wire the strategy
    /// at the call site (CLI/MCP entrypoint) — typically a small
    /// adapter around `Search.Index.getDocumentContent(uri:format:)`.
    public actor DocsResourceProvider: MCP.Core.ResourceProvider {
        /// Maximum number of resources returned in a single
        /// `listResources` page. Pinned by
        /// `DocsResourceProviderListResourcesFilterAndPagingTests`. The
        /// MCP cursor protocol (2025-06-18) makes pagination optional;
        /// we issue a `nextCursor` only when the underlying sorted
        /// result is strictly longer than `pageSize`.
        ///
        /// The current bundle yields ~1,000 sorted resources
        /// (~420 framework roots + 483 Swift Evolution proposals +
        /// 96 Apple Archive guides + a handful of curated entries), so
        /// 500 keeps the typical first page well under typical MCP
        /// client message-size limits without forcing every consumer
        /// to follow a cursor.
        public static let pageSize: Int = 500

        private let configuration: Shared.Configuration
        private var metadata: Shared.Models.CrawlMetadata?
        private let markdownLookup: (any MCP.Support.MarkdownLookupStrategy)?
        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        /// 2026-05-26 audit Cluster 12 follow-up: registry-supplied
        /// per-source URI resource strategies. Pre-fix the resource
        /// provider had 3 hardcoded `if uri.hasPrefix(...)` arms in
        /// `readResource` + 3 source-specific blocks in `listResources`
        /// (apple-docs / swift-evolution / apple-archive), each carrying
        /// 30-50 LOC of bespoke URI parsing + filesystem probing +
        /// (apple-docs only) JSON-vs-md decode logic. Post-fix each
        /// per-source target supplies its own
        /// `Search.URIResourceStrategy` concrete; the dispatcher
        /// iterates this list. Adding a new MCP-resource source is one
        /// `makeURIResourceStrategy()` override on the provider.
        private let resourceStrategies: [any Search.URIResourceStrategy]

        /// Per-scheme on-disk corpus directory. The composition root
        /// builds this from each provider's
        /// `fetchInfo.defaultOutputDirKey` resolved via `Shared.Paths`
        /// (honouring `--evolution-dir` + apple-docs CLI overrides).
        private let directoriesByScheme: [String: URL]

        /// Set of URI schemes the dispatcher recognises. Derived from
        /// `resourceStrategies.map(\.scheme)` so the set stays in sync
        /// with the strategies list automatically.
        public nonisolated let knownURISchemes: Set<String>

        public init(
            configuration: Shared.Configuration,
            resourceStrategies: [any Search.URIResourceStrategy],
            directoriesByScheme: [String: URL],
            markdownLookup: (any MCP.Support.MarkdownLookupStrategy)? = nil,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.configuration = configuration
            self.resourceStrategies = resourceStrategies
            self.directoriesByScheme = directoriesByScheme
            self.markdownLookup = markdownLookup
            self.logger = logger
            knownURISchemes = Set(resourceStrategies.map(\.scheme))
            // Metadata will be loaded lazily on first access
        }

        // MARK: - ResourceProvider

        public func listResources(cursor: String?) async throws -> MCP.Core.Protocols.ListResourcesResult {
            var resources: [MCP.Core.Protocols.Resource] = []

            // Apple-docs metadata is loaded lazily here (the only
            // strategy that consumes it; the swift-evolution +
            // apple-archive strategies enumerate the filesystem and
            // ignore the env's metadata field). The metadata load is
            // wrapped in the same do/catch that pre-fix surrounded the
            // apple-docs slice — bug #568 hid this branch by silently
            // swallowing the throw, post-fix we log loud-fail at .error
            // so `cupertino doctor` users can grep for it.
            var loadedMetadata: Shared.Models.CrawlMetadata?
            do {
                loadedMetadata = try await getMetadata()
            } catch {
                logger.error(
                    "DocsResourceProvider: apple-docs slice unavailable (\(error)); "
                        + "resources/list will exclude apple-docs entries this call",
                    category: .mcp
                )
            }

            // Per-strategy fan-out. Each strategy returns its own slice
            // of URIResource entries; the dispatcher maps to
            // MCP.Core.Protocols.Resource at the boundary. A strategy
            // whose directory is missing or unreadable contributes an
            // empty slice (and a debug-level log); the call still
            // returns everything else.
            for strategy in resourceStrategies {
                guard let directory = directoriesByScheme[strategy.scheme] else {
                    logger.warning(
                        "DocsResourceProvider: no directory configured for scheme '\(strategy.scheme)' "
                            + "— skipping that slice of resources/list",
                        category: .mcp
                    )
                    continue
                }
                let env = Search.URIResourceEnvironment(
                    sourceDirectory: directory,
                    metadata: loadedMetadata,
                    logger: logger
                )
                do {
                    let slice = try await strategy.listResources(env: env)
                    resources.append(contentsOf: slice.map { entry in
                        MCP.Core.Protocols.Resource(
                            uri: entry.uri,
                            name: entry.name,
                            description: entry.description,
                            mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown
                        )
                    })
                } catch {
                    // Source-specific listResources errors are
                    // non-fatal; the dispatcher carries on with the
                    // other slices. Pre-fix swift-evolution + apple-
                    // archive used a silent `catch {}` here — keep
                    // that behaviour for those slices but emit a
                    // debug-level log so the path isn't completely
                    // invisible.
                    logger.warning(
                        "DocsResourceProvider: \(strategy.scheme) slice failed: \(error)",
                        category: .mcp
                    )
                }
            }

            // Sort by name (stable input for pagination — same cursor
            // returns the same slice across calls).
            resources.sort { $0.name < $1.name }

            // Slice by cursor. Empty / nil cursor means "first page"
            // and is valid. Non-empty but malformed cursors throw
            // `invalidArgument` so a buggy client gets a JSON-RPC
            // error frame (`-32602`) instead of silently restarting
            // pagination on every call (#595). The MCP spec leaves the
            // cursor string opaque, but a server that silently swallows
            // bad cursors traps paginating clients in an infinite "first
            // page" loop — they never notice their cursor was wrong.
            let offset = try Self.decodeOffset(from: cursor)
            return paginate(resources, offset: offset)
        }

        // MARK: - Cursor pagination

        /// Slice `resources` starting at `offset`, returning at most
        /// `Self.pageSize` entries and a `nextCursor` if more remain.
        private func paginate(
            _ resources: [MCP.Core.Protocols.Resource],
            offset: Int
        ) -> MCP.Core.Protocols.ListResourcesResult {
            let safeOffset = max(0, min(offset, resources.count))
            let end = min(safeOffset + Self.pageSize, resources.count)
            let slice = Array(resources[safeOffset..<end])
            let nextCursor: String? = end < resources.count
                ? Self.encodeOffset(end)
                : nil
            return MCP.Core.Protocols.ListResourcesResult(resources: slice, nextCursor: nextCursor)
        }

        /// Encode an offset as an opaque base64 cursor. Format is
        /// `offset:<N>`, ASCII, base64-encoded, no padding stripped.
        /// Self-evident in debug while still opaque enough that
        /// clients won't grow a dependency on the internal format.
        static func encodeOffset(_ offset: Int) -> String {
            let payload = "offset:\(offset)"
            return Data(payload.utf8).base64EncodedString()
        }

        /// Decode a cursor produced by `encodeOffset`.
        ///
        /// - `nil` or empty cursor → returns 0 (means "first page" —
        ///   the valid no-cursor case).
        /// - Non-empty cursor that doesn't decode (not base64, wrong
        ///   prefix, negative offset, non-integer payload, …) → throws
        ///   `Shared.Core.ToolError.invalidArgument("cursor", ...)`.
        ///   That surfaces to the JSON-RPC layer as a `-32602
        ///   invalidParams` error frame, which is the correct behaviour
        ///   for a malformed pagination cursor (#595). Pre-fix this
        ///   returned 0 silently and trapped paginating clients in an
        ///   endless loop of re-fetching page 1.
        static func decodeOffset(from cursor: String?) throws -> Int {
            // No cursor = "first page". This is the valid bootstrap call.
            guard let cursor, !cursor.isEmpty else { return 0 }
            // Cursor present — must decode cleanly, no silent fallback.
            guard let data = Data(base64Encoded: cursor),
                  let decoded = String(data: data, encoding: .utf8),
                  decoded.hasPrefix("offset:"),
                  let offset = Int(decoded.dropFirst("offset:".count)),
                  offset >= 0
            else {
                throw Shared.Core.ToolError.invalidArgument(
                    "cursor",
                    "Malformed cursor: \(cursor)"
                )
            }
            return offset
        }

        // MARK: - Filter

        public func readResource(uri: String) async throws -> MCP.Core.Protocols.ReadResourceResult {
            // Principle 7: resolve content from the DB only — never the
            // filesystem. There is no fallback. A document that isn't in the
            // DB is `notFound`; tests guarantee the indexer puts it there.
            guard let markdownLookup else {
                throw Shared.Core.ToolError.notFound(uri)
            }
            guard let dbContent = try await markdownLookup.lookup(uri: uri) else {
                throw Shared.Core.ToolError.notFound(uri)
            }
            let contents = MCP.Core.Protocols.ResourceContents.text(
                MCP.Core.Protocols.TextResourceContents(
                    uri: uri,
                    mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown,
                    text: dbContent
                )
            )
            return MCP.Core.Protocols.ReadResourceResult(contents: [contents])
        }

        public func listResourceTemplates(
            cursor _: String?
        ) async throws -> MCP.Core.Protocols.ListResourceTemplatesResult? {
            let templates = [
                MCP.Core.Protocols.ResourceTemplate(
                    uriTemplate: MCP.SharedTools.Copy.templateAppleDocs,
                    name: MCP.SharedTools.Copy.appleDocsTemplateName,
                    description: MCP.SharedTools.Copy.appleDocsTemplateDescription,
                    mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown
                ),
                MCP.Core.Protocols.ResourceTemplate(
                    uriTemplate: MCP.SharedTools.Copy.templateSwiftEvolution,
                    name: MCP.SharedTools.Copy.swiftEvolutionDescription,
                    description: MCP.SharedTools.Copy.swiftEvolutionTemplateDescription,
                    mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown
                ),
            ]

            return MCP.Core.Protocols.ListResourceTemplatesResult(resourceTemplates: templates)
        }

        // MARK: - Private Methods

        private func loadMetadata() {
            let metadataURL = configuration.changeDetection.metadataFile

            // #568 retrospective: the previous shape was a silent
            // early-return when the file was missing and a `.warning`
            // log when the parse threw. That combination is exactly
            // how the v1.1.0 brew binary masked the bug — the
            // outermost catch in `listResources` then swallowed the
            // `noData` throw and the user saw a swift-evolution-only
            // list. Both miss-paths now log at `.error` with full
            // context so `cupertino doctor` and ad-hoc grep can spot
            // them.
            guard FileManager.default.fileExists(atPath: metadataURL.path) else {
                logger.error(
                    "DocsResourceProvider: metadata file absent at '\(metadataURL.path)'; "
                        + "apple-docs slice of resources/list will be empty",
                    category: .mcp
                )
                return
            }

            do {
                metadata = try Shared.Models.CrawlMetadata.load(from: metadataURL)
            } catch {
                logger.error(
                    "DocsResourceProvider: failed to parse metadata at '\(metadataURL.path)' "
                        + "(\(error)); apple-docs slice of resources/list will be empty",
                    category: .mcp
                )
            }
        }

        // MARK: - Test Support

        /// Seed the cached metadata directly. Test-only path so MCPSupportTests
        /// can exercise `listResources` against a hand-crafted `CrawlMetadata`
        /// (including malformed-URL rows) without bootstrapping a real
        /// crawl + metadata.json fixture on disk.
        func injectMetadataForTesting(_ metadata: Shared.Models.CrawlMetadata) {
            self.metadata = metadata
        }

        // MARK: - Metadata

        private func getMetadata() async throws -> Shared.Models.CrawlMetadata {
            if let metadata {
                return metadata
            }

            // Reload if not cached
            loadMetadata()

            guard let metadata else {
                let cmd = "\(Shared.Constants.App.commandName) \(Shared.Constants.Command.crawl)"
                throw Shared.Core.ToolError.noData("No documentation has been crawled yet. Run '\(cmd)' first.")
            }

            return metadata
        }

        // 2026-05-26 audit Cluster 12 follow-up: `parseAppleDocsURI`,
        // `parseEvolutionURI`, `parseArchiveURI`, `extractTitle`,
        // `isFrameworkRootPage`, and `listArchiveResources` lifted into
        // per-source `Search.URIResourceStrategy` concretes
        // (`AppleDocsURIResourceStrategy` /
        // `SwiftEvolutionURIResourceStrategy` /
        // `AppleArchiveURIResourceStrategy`). Adding a new MCP-resource
        // source no longer requires editing this file.
    }
}
