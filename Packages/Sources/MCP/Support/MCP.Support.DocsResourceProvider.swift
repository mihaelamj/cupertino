import Foundation
import LoggingModels
import MCPCore
import MCPSharedTools
import SharedConfiguration
import SharedConstants
import SharedModels
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

            // Add Apple Documentation resources
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
                    let uri = "\(Shared.Constants.Search.appleDocsScheme)\(pageMetadata.framework)/"
                        + "\(Shared.Models.URLUtilities.filename(from: parsedURL))"
                    let resource = MCP.Core.Protocols.Resource(
                        uri: uri,
                        name: extractTitle(from: url),
                        description: "\(MCP.SharedTools.Copy.appleDocsDescriptionPrefix) \(pageMetadata.framework)",
                        mimeType: MCP.SharedTools.Copy.mimeTypeMarkdown
                    )
                    resources.append(resource)
                }
            } catch {
                // If Apple docs aren't available, that's OK - we might only have Evolution proposals
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

            // Sort by name
            resources.sort { $0.name < $1.name }

            return MCP.Core.Protocols.ListResourcesResult(resources: resources)
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

            guard FileManager.default.fileExists(atPath: metadataURL.path) else {
                return
            }

            do {
                metadata = try Shared.Models.CrawlMetadata.load(from: metadataURL)
            } catch {
                logger.warning("Failed to load metadata: \(error)", category: .mcp)
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
