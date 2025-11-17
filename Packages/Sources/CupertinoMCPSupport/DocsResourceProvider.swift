import CupertinoShared
import Foundation
import MCPServer
import MCPShared

// MARK: - Documentation Resource Provider

/// Provides crawled documentation as MCP resources
public actor DocsResourceProvider: ResourceProvider {
    private let configuration: CupertinoConfiguration
    private var metadata: CrawlMetadata?
    private let evolutionDirectory: URL

    public init(configuration: CupertinoConfiguration, evolutionDirectory: URL? = nil) {
        self.configuration = configuration
        self.evolutionDirectory = evolutionDirectory ?? CupertinoConstants.defaultSwiftEvolutionDirectory
        // Metadata will be loaded lazily on first access
    }

    // MARK: - ResourceProvider

    public func listResources(cursor: String?) async throws -> ListResourcesResult {
        var resources: [Resource] = []

        // Add Apple Documentation resources
        do {
            let metadata = try await getMetadata()

            for (url, pageMetadata) in metadata.pages {
                let uri = "\(CupertinoConstants.MCP.appleDocsScheme)\(pageMetadata.framework)/"
                    + "\(URLUtilities.filename(from: URL(string: url)!))"
                let resource = Resource(
                    uri: uri,
                    name: extractTitle(from: url),
                    description: "\(CupertinoConstants.MCP.appleDocsDescriptionPrefix) \(pageMetadata.framework)",
                    mimeType: CupertinoConstants.MCP.mimeTypeMarkdown
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
                    && file.lastPathComponent.hasPrefix(CupertinoConstants.MCP.sePrefix) {
                    let proposalID = file.deletingPathExtension().lastPathComponent
                    let resource = Resource(
                        uri: "\(CupertinoConstants.MCP.swiftEvolutionScheme)\(proposalID)",
                        name: proposalID,
                        description: CupertinoConstants.MCP.swiftEvolutionDescription,
                        mimeType: CupertinoConstants.MCP.mimeTypeMarkdown
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
        let filePath: URL
        let markdown: String

        if uri.hasPrefix(CupertinoConstants.MCP.appleDocsScheme) {
            // Parse URI: apple-docs://framework/filename
            guard let components = parseAppleDocsURI(uri) else {
                throw ResourceError.invalidURI(uri)
            }

            // Find the file
            filePath = configuration.crawler.outputDirectory
                .appendingPathComponent(components.framework)
                .appendingPathComponent("\(components.filename)\(CupertinoConstants.FileName.markdownExtension)")

            guard FileManager.default.fileExists(atPath: filePath.path) else {
                throw ResourceError.notFound(uri)
            }

            // Read markdown content
            markdown = try String(contentsOf: filePath, encoding: .utf8)

        } else if uri.hasPrefix(CupertinoConstants.MCP.swiftEvolutionScheme) {
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

            // Read markdown content
            markdown = try String(contentsOf: file, encoding: .utf8)

        } else {
            throw ResourceError.invalidURI(uri)
        }

        // Create resource contents
        let contents = ResourceContents.text(
            TextResourceContents(
                uri: uri,
                mimeType: CupertinoConstants.MCP.mimeTypeMarkdown,
                text: markdown
            )
        )

        return ReadResourceResult(contents: [contents])
    }

    public func listResourceTemplates(cursor: String?) async throws -> ListResourceTemplatesResult? {
        let templates = [
            ResourceTemplate(
                uriTemplate: CupertinoConstants.MCP.templateAppleDocs,
                name: CupertinoConstants.MCP.appleDocsTemplateName,
                description: CupertinoConstants.MCP.appleDocsTemplateDescription,
                mimeType: CupertinoConstants.MCP.mimeTypeMarkdown
            ),
            ResourceTemplate(
                uriTemplate: CupertinoConstants.MCP.templateSwiftEvolution,
                name: CupertinoConstants.MCP.swiftEvolutionDescription,
                description: CupertinoConstants.MCP.swiftEvolutionTemplateDescription,
                mimeType: CupertinoConstants.MCP.mimeTypeMarkdown
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
            print("⚠️  Failed to load metadata: \(error)")
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
        guard uri.hasPrefix(CupertinoConstants.MCP.appleDocsScheme) else {
            return nil
        }

        let path = uri.replacingOccurrences(of: CupertinoConstants.MCP.appleDocsScheme, with: "")
        let components = path.split(separator: "/", maxSplits: 1)

        guard components.count == 2 else {
            return nil
        }

        return (framework: String(components[0]), filename: String(components[1]))
    }

    private func parseEvolutionURI(_ uri: String) -> String? {
        // Expected format: swift-evolution://SE-NNNN
        guard uri.hasPrefix(CupertinoConstants.MCP.swiftEvolutionScheme) else {
            return nil
        }

        let proposalID = uri.replacingOccurrences(of: CupertinoConstants.MCP.swiftEvolutionScheme, with: "")
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
                + "Run '\(CupertinoConstants.App.commandName) \(CupertinoConstants.Command.crawl)' first."
        }
    }
}
