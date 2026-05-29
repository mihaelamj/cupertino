import Foundation
import LoggingModels
import MCPCore
import MCPSharedTools
import SearchModels
import SharedConstants

// MARK: - Documentation Resource Provider

extension MCP.Support {
    /// Strategy for resolving + enumerating MCP resources purely out of
    /// the per-source SQLite databases. GoF Strategy pattern (1994
    /// p. 315): the provider names the contract, the composition root
    /// supplies the concrete that reaches the per-source DBs.
    ///
    /// Principle 7 (`docs/PRINCIPLES.md`): the database is the single
    /// source of truth. Both methods resolve content / enumeration from
    /// the DBs alone; no filesystem path is ever consulted. A document
    /// absent from the DB is `notFound`; the resources list is whatever
    /// the per-source DBs can enumerate.
    ///
    /// Replaces the previous
    /// `MarkdownLookup = @Sendable (String) async throws -> String?`
    /// closure typealias. Conforming types name the contract, make
    /// captured state explicit, and produce one-line test mocks instead
    /// of inline closures.
    public protocol MarkdownLookupStrategy: Sendable {
        /// Resolve a URI to its pre-rendered markdown out of the matching
        /// per-source DB. Returns `nil` when the URI is not present (the
        /// provider maps that to `notFound`); throws on a real DB error.
        func lookup(uri: String) async throws -> String?

        /// Enumerate every MCP resource the per-source DBs can list.
        /// Each entry's `uri` is directly readable via `lookup(uri:)`.
        /// Enumeration is DB-backed; no filesystem is consulted.
        func listResources() async throws -> [Search.URIResource]
    }

    /// Provides crawled documentation as MCP resources.
    ///
    /// The provider's read + list behaviour is injected as a
    /// `MarkdownLookupStrategy` conformer rather than a concrete
    /// `Search.Index` value, so this target stays free of any
    /// behavioural dependency on Search. The composition root
    /// (CLI `serve`) wires the per-source-DB-backed concrete.
    public actor DocsResourceProvider: MCP.Core.ResourceProvider {
        /// Maximum number of resources returned in a single
        /// `listResources` page. Pinned by
        /// `DocsResourceProviderListResourcesFilterAndPagingTests`. The
        /// MCP cursor protocol (2025-06-18) makes pagination optional;
        /// we issue a `nextCursor` only when the underlying sorted
        /// result is strictly longer than `pageSize`.
        public static let pageSize: Int = 500

        private let markdownLookup: (any MCP.Support.MarkdownLookupStrategy)?
        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        /// Set of URI schemes the provider advertises. Supplied by the
        /// composition root from the registered docs-tier sources'
        /// schemes so the set stays in sync with the production source
        /// registry. Kept as a value (not derived from a filesystem
        /// strategy list) so the resources path touches no disk.
        public nonisolated let knownURISchemes: Set<String>

        public init(
            knownURISchemes: Set<String> = [],
            markdownLookup: (any MCP.Support.MarkdownLookupStrategy)? = nil,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.knownURISchemes = knownURISchemes
            self.markdownLookup = markdownLookup
            self.logger = logger
        }

        // MARK: - ResourceProvider

        public func listResources(cursor: String?) async throws -> MCP.Core.Protocols.ListResourcesResult {
            // Principle 7: enumerate from the per-source DBs only — never
            // the filesystem. With no lookup wired the list is empty
            // (no DBs to enumerate).
            guard let markdownLookup else {
                return MCP.Core.Protocols.ListResourcesResult(resources: [], nextCursor: nil)
            }

            let entries: [Search.URIResource]
            do {
                entries = try await markdownLookup.listResources()
            } catch {
                // DB enumeration errors are non-fatal: log loud-fail at
                // .error (so `cupertino doctor` users can grep for it)
                // and return an empty page rather than failing the whole
                // call.
                logger.error(
                    "DocsResourceProvider: resources/list DB enumeration failed (\(error)); "
                        + "returning an empty page this call",
                    category: .mcp
                )
                return MCP.Core.Protocols.ListResourcesResult(resources: [], nextCursor: nil)
            }

            var resources = entries.map { entry in
                MCP.Core.Protocols.Resource(
                    uri: entry.uri,
                    name: entry.name,
                    description: entry.description,
                    mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown
                )
            }

            // Sort by name (stable input for pagination — same cursor
            // returns the same slice across calls).
            resources.sort { $0.name < $1.name }

            // Slice by cursor. Empty / nil cursor means "first page"
            // and is valid. Non-empty but malformed cursors throw
            // `invalidArgument` so a buggy client gets a JSON-RPC
            // error frame (`-32602`) instead of silently restarting
            // pagination on every call (#595).
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
        ///   for a malformed pagination cursor (#595).
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

        // MARK: - readResource

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
    }
}
