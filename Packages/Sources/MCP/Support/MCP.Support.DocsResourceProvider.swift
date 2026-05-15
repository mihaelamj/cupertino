import Foundation
import LoggingModels
import MCPCore
import MCPSharedTools
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
        private let evolutionDirectory: URL
        private let archiveDirectory: URL
        private let markdownLookup: (any MCP.Support.MarkdownLookupStrategy)?
        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        /// Strict-DI constructor (#535): every directory is supplied by the
        /// caller's composition root. The previous nil-default + fallback
        /// to `Shared.Constants.default*` (which routed through the
        /// `BinaryConfig.shared` Singleton) is gone — callers must thread
        /// the URLs through explicitly.
        public init(
            configuration: Shared.Configuration,
            evolutionDirectory: URL,
            archiveDirectory: URL,
            markdownLookup: (any MCP.Support.MarkdownLookupStrategy)? = nil,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.configuration = configuration
            self.evolutionDirectory = evolutionDirectory
            self.archiveDirectory = archiveDirectory
            self.markdownLookup = markdownLookup
            self.logger = logger
            // Metadata will be loaded lazily on first access
        }

        // MARK: - ResourceProvider

        public func listResources(cursor: String?) async throws -> MCP.Core.Protocols.ListResourcesResult {
            var resources: [MCP.Core.Protocols.Resource] = []

            // Add Apple Documentation resources.
            //
            // Bug #568 fix: iterate `metadata.pages` with the
            // framework-root filter applied. Pre-fix this loop ran on
            // every page in the corpus (~55k entries on the live
            // bundle), turning each deep symbol page into a noisy
            // resource. Only one resource per framework belongs in
            // `resources/list`; deep pages are reachable through
            // `tools/call search` + `readResource` with a precise
            // `apple-docs://framework/symbol` URI.
            //
            // The do/catch around `getMetadata()` used to swallow the
            // throw silently, which is how v1.1.0 hid this regression
            // (the apple-docs slice quietly evaporated and the user
            // saw a swift-evolution-only list). Now we log at .error
            // level so the failure is visible in normal operation
            // without breaking the "evolution + archive still work
            // when the docs corpus is absent" UX.
            do {
                let metadata = try await getMetadata()

                for (url, pageMetadata) in metadata.pages {
                    // `url` comes from indexed page metadata; skip rows whose key
                    // doesn't parse rather than crashing the resource listing.
                    // The other two skip sites (SearchIndexBuilder,
                    // SampleCodeDownloader) log the skip; matching that here so
                    // a degraded listing doesn't go unnoticed.
                    guard let parsedURL = URL(string: url) else {
                        logger.warning(
                            "Skipping malformed URL key in CrawlMetadata.pages: '\(url)' "
                                + "(framework: \(pageMetadata.framework))",
                            category: .mcp
                        )
                        continue
                    }
                    guard isFrameworkRootPage(url: parsedURL, framework: pageMetadata.framework) else {
                        continue
                    }
                    // #587 / BUG 1 fix: use the lossless `appleDocsURI(from:)`
                    // helper. The resources/list URI MUST match the
                    // indexer-stored URI in `docs_metadata` so that
                    // `resources/read` and `read_document` lookups
                    // resolve. Both surfaces now route through the same
                    // helper.
                    let uri = Shared.Models.URLUtilities.appleDocsURI(from: parsedURL)
                        ?? "\(Shared.Constants.Search.appleDocsScheme)\(pageMetadata.framework)/\(Shared.Models.URLUtilities.filename(from: parsedURL))"
                    let resource = MCP.Core.Protocols.Resource(
                        uri: uri,
                        name: extractTitle(from: url),
                        description: "\(MCP.SharedTools.Copy.appleDocsDescriptionPrefix) \(pageMetadata.framework)",
                        mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown
                    )
                    resources.append(resource)
                }
            } catch {
                // Loud-fail surface for the apple-docs slice. The
                // call still returns the evolution + archive resources
                // it can build from disk; `cupertino doctor` users
                // can grep for this line to confirm the corpus is
                // absent / unreadable.
                logger.error(
                    "DocsResourceProvider: apple-docs slice unavailable (\(error)); "
                        + "resources/list will exclude apple-docs entries this call",
                    category: .mcp
                )
            }

            // Add Swift Evolution proposals
            if FileManager.default.fileExists(atPath: evolutionDirectory.path) {
                do {
                    let files = try FileManager.default.contentsOfDirectory(
                        at: evolutionDirectory,
                        includingPropertiesForKeys: nil
                    )

                    for file in files where file.pathExtension == "md"
                        && (file.lastPathComponent.hasPrefix(Shared.Constants.Search.sePrefix) ||
                            file.lastPathComponent.hasPrefix(Shared.Constants.Search.stPrefix)) {
                        let proposalID = file.deletingPathExtension().lastPathComponent
                        let resource = MCP.Core.Protocols.Resource(
                            uri: "\(Shared.Constants.Search.swiftEvolutionScheme)\(proposalID)",
                            name: proposalID,
                            description: MCP.SharedTools.Copy.swiftEvolutionDescription,
                            mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown
                        )
                        resources.append(resource)
                    }
                } catch {
                    // Evolution proposals directory doesn't exist or can't be read
                }
            }

            // Add Apple Archive documentation
            if FileManager.default.fileExists(atPath: archiveDirectory.path) {
                do {
                    let archiveResources = try listArchiveResources()
                    resources.append(contentsOf: archiveResources)
                } catch {
                    // Archive directory doesn't exist or can't be read
                }
            }

            // Sort by name (stable input for pagination — same cursor
            // returns the same slice across calls).
            resources.sort { $0.name < $1.name }

            // Slice by cursor. Bad cursors fall back to the first page
            // rather than throwing — the MCP spec leaves the cursor
            // string opaque, and a paranoid client recovers naturally
            // from "I lost my cursor" by re-requesting from scratch.
            let offset = Self.decodeOffset(from: cursor)
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

        /// Decode a cursor produced by `encodeOffset`. Bad input
        /// (nil, not base64, wrong format, negative offset, NaN, …)
        /// returns 0 so the caller serves the first page.
        static func decodeOffset(from cursor: String?) -> Int {
            guard let cursor,
                  !cursor.isEmpty,
                  let data = Data(base64Encoded: cursor),
                  let decoded = String(data: data, encoding: .utf8),
                  decoded.hasPrefix("offset:"),
                  let offset = Int(decoded.dropFirst("offset:".count)),
                  offset >= 0
            else {
                return 0
            }
            return offset
        }

        // MARK: - Filter

        /// Returns `true` when `url` points at a framework root page —
        /// the only apple-docs entries that belong in
        /// `resources/list`. A framework root has path exactly
        /// `/documentation/<framework>` (case-insensitive on the
        /// framework segment to absorb Apple's mixed-case JSON
        /// responses), with an optional trailing slash.
        ///
        /// Returns `false` for deep symbol pages
        /// (`/documentation/<framework>/<member>`), the docs root
        /// (`/documentation` with no framework), and anything else.
        private func isFrameworkRootPage(url: URL, framework: String) -> Bool {
            let normalizedPath = url.path.hasSuffix("/")
                ? String(url.path.dropLast())
                : url.path
            let expected = "/documentation/\(framework.lowercased())"
            return normalizedPath.lowercased() == expected
        }

        public func readResource(uri: String) async throws -> MCP.Core.Protocols.ReadResourceResult {
            let markdown: String

            // Try database first if a markdown lookup was injected
            if let markdownLookup {
                if let dbContent = try await markdownLookup.lookup(uri: uri) {
                    // Found in database - return markdown
                    let contents = MCP.Core.Protocols.ResourceContents.text(
                        MCP.Core.Protocols.TextResourceContents(
                            uri: uri,
                            mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown,
                            text: dbContent
                        )
                    )
                    return MCP.Core.Protocols.ReadResourceResult(contents: [contents])
                }
            }

            // Database lookup failed or no index - fall back to filesystem
            if uri.hasPrefix(Shared.Constants.Search.appleDocsScheme) {
                // Parse URI: apple-docs://framework/filename
                guard let components = parseAppleDocsURI(uri) else {
                    throw Shared.Core.ToolError.invalidURI(uri)
                }

                let baseDir = configuration.crawler.outputDirectory
                    .appendingPathComponent(components.framework)

                // Try JSON file first (new format), then fall back to MD (old format)
                let jsonPath = baseDir.appendingPathComponent("\(components.filename).json")
                let mdFilename = "\(components.filename)\(Shared.Constants.FileName.markdownExtension)"
                let mdPath = baseDir.appendingPathComponent(mdFilename)

                if FileManager.default.fileExists(atPath: jsonPath.path) {
                    // Read JSON and extract rawMarkdown
                    let jsonData = try Data(contentsOf: jsonPath)
                    let page = try Shared.Utils.JSONCoding.decode(Shared.Models.StructuredDocumentationPage.self, from: jsonData)
                    guard let rawMarkdown = page.rawMarkdown else {
                        throw Shared.Core.ToolError.notFound(uri)
                    }
                    markdown = rawMarkdown
                } else if FileManager.default.fileExists(atPath: mdPath.path) {
                    // Fall back to markdown file
                    markdown = try String(contentsOf: mdPath, encoding: .utf8)
                } else {
                    throw Shared.Core.ToolError.notFound(uri)
                }

            } else if uri.hasPrefix(Shared.Constants.Search.swiftEvolutionScheme) {
                // Parse URI: swift-evolution://SE-NNNN
                guard let proposalID = parseEvolutionURI(uri) else {
                    throw Shared.Core.ToolError.invalidURI(uri)
                }

                // Find the proposal file
                let files = try FileManager.default.contentsOfDirectory(
                    at: evolutionDirectory,
                    includingPropertiesForKeys: nil
                )

                guard let file = files.first(where: { $0.lastPathComponent.hasPrefix(proposalID) }) else {
                    throw Shared.Core.ToolError.notFound(uri)
                }

                // Read markdown content from filesystem
                markdown = try String(contentsOf: file, encoding: .utf8)

            } else if uri.hasPrefix(Shared.Constants.Search.appleArchiveScheme) {
                // Parse URI: apple-archive://guideUID/filename
                guard let components = parseArchiveURI(uri) else {
                    throw Shared.Core.ToolError.invalidURI(uri)
                }

                // Construct file path: archive/{guideUID}/{filename}.md
                let filePath = archiveDirectory
                    .appendingPathComponent(components.guideUID)
                    .appendingPathComponent("\(components.filename).md")

                guard FileManager.default.fileExists(atPath: filePath.path) else {
                    throw Shared.Core.ToolError.notFound(uri)
                }

                markdown = try String(contentsOf: filePath, encoding: .utf8)

            } else {
                throw Shared.Core.ToolError.invalidURI(uri)
            }

            // Create resource contents
            let contents = MCP.Core.Protocols.ResourceContents.text(
                MCP.Core.Protocols.TextResourceContents(
                    uri: uri,
                    mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown,
                    text: markdown
                )
            )

            return MCP.Core.Protocols.ReadResourceResult(contents: [contents])
        }

        public func listResourceTemplates(cursor: String?) async throws -> MCP.Core.Protocols.ListResourceTemplatesResult? {
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

        private func parseAppleDocsURI(_ uri: String) -> (framework: String, filename: String)? {
            // Expected format: apple-docs://framework/filename
            guard uri.hasPrefix(Shared.Constants.Search.appleDocsScheme) else {
                return nil
            }

            let path = uri.replacingOccurrences(of: Shared.Constants.Search.appleDocsScheme, with: "")
            let components = path.split(separator: "/", maxSplits: 1)

            guard components.count == 2 else {
                return nil
            }

            return (framework: String(components[0]), filename: String(components[1]))
        }

        private func parseEvolutionURI(_ uri: String) -> String? {
            // Expected format: swift-evolution://SE-NNNN
            guard uri.hasPrefix(Shared.Constants.Search.swiftEvolutionScheme) else {
                return nil
            }

            let proposalID = uri.replacingOccurrences(of: Shared.Constants.Search.swiftEvolutionScheme, with: "")
            return proposalID.isEmpty ? nil : proposalID
        }

        private func extractTitle(from urlString: String) -> String {
            guard let url = URL(string: urlString) else {
                return urlString
            }

            // Get the last path component and clean it up
            let lastComponent = url.lastPathComponent
            return lastComponent
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        private func listArchiveResources() throws -> [MCP.Core.Protocols.Resource] {
            var resources: [MCP.Core.Protocols.Resource] = []

            let guides = try FileManager.default.contentsOfDirectory(
                at: archiveDirectory,
                includingPropertiesForKeys: nil
            )

            for guide in guides where guide.hasDirectoryPath {
                let guideUID = guide.lastPathComponent
                let files = try FileManager.default.contentsOfDirectory(
                    at: guide,
                    includingPropertiesForKeys: nil
                )

                for file in files where file.pathExtension == "md" {
                    let filename = file.deletingPathExtension().lastPathComponent
                    let uri = "\(Shared.Constants.Search.appleArchiveScheme)\(guideUID)/\(filename)"
                    let resource = MCP.Core.Protocols.Resource(
                        uri: uri,
                        name: filename.replacingOccurrences(of: "-", with: " ").capitalized,
                        description: "Apple Archive documentation",
                        mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown
                    )
                    resources.append(resource)
                }
            }

            return resources
        }

        private func parseArchiveURI(_ uri: String) -> (guideUID: String, filename: String)? {
            // Expected format: apple-archive://guideUID/filename
            guard uri.hasPrefix(Shared.Constants.Search.appleArchiveScheme) else {
                return nil
            }

            let path = uri.replacingOccurrences(of: Shared.Constants.Search.appleArchiveScheme, with: "")
            let components = path.split(separator: "/", maxSplits: 1)

            guard components.count == 2 else {
                return nil
            }

            return (guideUID: String(components[0]), filename: String(components[1]))
        }
    }
}
