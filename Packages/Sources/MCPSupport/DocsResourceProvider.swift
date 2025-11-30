import Foundation
import Logging
import MCP
import Search
import Shared

// MARK: - Documentation Resource Provider

/// Provides crawled documentation as MCP resources
public actor DocsResourceProvider: ResourceProvider {
    private let configuration: Shared.Configuration
    private var metadata: CrawlMetadata?
    private let evolutionDirectory: URL
    private let searchIndex: Search.Index?

    public init(
        configuration: Shared.Configuration,
        evolutionDirectory: URL? = nil,
        searchIndex: Search.Index? = nil
    ) {
        self.configuration = configuration
        self.evolutionDirectory = evolutionDirectory ?? Shared.Constants.defaultSwiftEvolutionDirectory
        self.searchIndex = searchIndex
        // Metadata will be loaded lazily on first access
    }

    // MARK: - ResourceProvider

    public func listResources(cursor: String?) async throws -> ListResourcesResult {
        var resources: [Resource] = []

        // Add Apple Documentation resources
        do {
            let metadata = try await getMetadata()

            for (url, pageMetadata) in metadata.pages {
                let uri = "\(Shared.Constants.MCP.appleDocsScheme)\(pageMetadata.framework)/"
                    + "\(URLUtilities.filename(from: URL(string: url)!))"
                let resource = Resource(
                    uri: uri,
                    name: extractTitle(from: url),
                    description: "\(Shared.Constants.MCP.appleDocsDescriptionPrefix) \(pageMetadata.framework)",
                    mimeType: Shared.Constants.MCP.mimeTypeMarkdown
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
                    && file.lastPathComponent.hasPrefix(Shared.Constants.MCP.sePrefix) {
                    let proposalID = file.deletingPathExtension().lastPathComponent
                    let resource = Resource(
                        uri: "\(Shared.Constants.MCP.swiftEvolutionScheme)\(proposalID)",
                        name: proposalID,
                        description: Shared.Constants.MCP.swiftEvolutionDescription,
                        mimeType: Shared.Constants.MCP.mimeTypeMarkdown
                    )
                    resources.append(resource)
                }
            } catch {
                // Evolution proposals directory doesn't exist or can't be read
            }
        }

        // Sort by name
        resources.sort { $0.name < $1.name }

        return ListResourcesResult(resources: resources)
    }

    public func readResource(uri: String) async throws -> ReadResourceResult {
        let markdown: String

        // Try database first if search index is available
        if let searchIndex {
            if let dbContent = try await searchIndex.getDocumentContent(uri: uri, format: .markdown) {
                // Found in database - return markdown
                let contents = ResourceContents.text(
                    TextResourceContents(
                        uri: uri,
                        mimeType: Shared.Constants.MCP.mimeTypeMarkdown,
                        text: dbContent
                    )
                )
                return ReadResourceResult(contents: [contents])
            }
        }

        // Database lookup failed or no index - fall back to filesystem
        if uri.hasPrefix(Shared.Constants.MCP.appleDocsScheme) {
            // Parse URI: apple-docs://framework/filename
            guard let components = parseAppleDocsURI(uri) else {
                throw ResourceError.invalidURI(uri)
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
                let page = try JSONCoding.decode(StructuredDocumentationPage.self, from: jsonData)
                guard let rawMarkdown = page.rawMarkdown else {
                    throw ResourceError.notFound(uri)
                }
                markdown = rawMarkdown
            } else if FileManager.default.fileExists(atPath: mdPath.path) {
                // Fall back to markdown file
                markdown = try String(contentsOf: mdPath, encoding: .utf8)
            } else {
                throw ResourceError.notFound(uri)
            }

        } else if uri.hasPrefix(Shared.Constants.MCP.swiftEvolutionScheme) {
            // Parse URI: swift-evolution://SE-NNNN
            guard let proposalID = parseEvolutionURI(uri) else {
                throw ResourceError.invalidURI(uri)
            }

            // Find the proposal file
            let files = try FileManager.default.contentsOfDirectory(
                at: evolutionDirectory,
                includingPropertiesForKeys: nil
            )

            guard let file = files.first(where: { $0.lastPathComponent.hasPrefix(proposalID) }) else {
                throw ResourceError.notFound(uri)
            }

            // Read markdown content from filesystem
            markdown = try String(contentsOf: file, encoding: .utf8)

        } else {
            throw ResourceError.invalidURI(uri)
        }

        // Create resource contents
        let contents = ResourceContents.text(
            TextResourceContents(
                uri: uri,
                mimeType: Shared.Constants.MCP.mimeTypeMarkdown,
                text: markdown
            )
        )

        return ReadResourceResult(contents: [contents])
    }

    public func listResourceTemplates(cursor: String?) async throws -> ListResourceTemplatesResult? {
        let templates = [
            ResourceTemplate(
                uriTemplate: Shared.Constants.MCP.templateAppleDocs,
                name: Shared.Constants.MCP.appleDocsTemplateName,
                description: Shared.Constants.MCP.appleDocsTemplateDescription,
                mimeType: Shared.Constants.MCP.mimeTypeMarkdown
            ),
            ResourceTemplate(
                uriTemplate: Shared.Constants.MCP.templateSwiftEvolution,
                name: Shared.Constants.MCP.swiftEvolutionDescription,
                description: Shared.Constants.MCP.swiftEvolutionTemplateDescription,
                mimeType: Shared.Constants.MCP.mimeTypeMarkdown
            ),
        ]

        return ListResourceTemplatesResult(resourceTemplates: templates)
    }

    // MARK: - Private Methods

    private func loadMetadata() {
        let metadataURL = configuration.changeDetection.metadataFile

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return
        }

        do {
            metadata = try CrawlMetadata.load(from: metadataURL)
        } catch {
            Log.warning("Failed to load metadata: \(error)", category: .mcp)
        }
    }

    private func getMetadata() async throws -> CrawlMetadata {
        if let metadata {
            return metadata
        }

        // Reload if not cached
        loadMetadata()

        guard let metadata else {
            throw ResourceError.noDocumentation
        }

        return metadata
    }

    private func parseAppleDocsURI(_ uri: String) -> (framework: String, filename: String)? {
        // Expected format: apple-docs://framework/filename
        guard uri.hasPrefix(Shared.Constants.MCP.appleDocsScheme) else {
            return nil
        }

        let path = uri.replacingOccurrences(of: Shared.Constants.MCP.appleDocsScheme, with: "")
        let components = path.split(separator: "/", maxSplits: 1)

        guard components.count == 2 else {
            return nil
        }

        return (framework: String(components[0]), filename: String(components[1]))
    }

    private func parseEvolutionURI(_ uri: String) -> String? {
        // Expected format: swift-evolution://SE-NNNN
        guard uri.hasPrefix(Shared.Constants.MCP.swiftEvolutionScheme) else {
            return nil
        }

        let proposalID = uri.replacingOccurrences(of: Shared.Constants.MCP.swiftEvolutionScheme, with: "")
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
}

// MARK: - Resource Errors

enum ResourceError: Error, LocalizedError {
    case invalidURI(String)
    case notFound(String)
    case noDocumentation

    var errorDescription: String? {
        switch self {
        case .invalidURI(let uri):
            return "Invalid resource URI: \(uri)"
        case .notFound(let uri):
            return "Resource not found: \(uri)"
        case .noDocumentation:
            return "No documentation has been crawled yet. "
                + "Run '\(Shared.Constants.App.commandName) \(Shared.Constants.Command.crawl)' first."
        }
    }
}
