import Foundation
import MCP
import Search
import Shared

// MARK: - Documentation Search Tool Provider

/// Provides search tools for MCP clients to query documentation
public actor DocumentationToolProvider: ToolProvider {
    private let searchIndex: Search.Index

    public init(searchIndex: Search.Index) {
        self.searchIndex = searchIndex
    }

    // MARK: - ToolProvider

    public func listTools(cursor: String?) async throws -> ListToolsResult {
        let tools = [
            Tool(
                name: Shared.Constants.MCP.toolSearchDocs,
                description: Shared.Constants.MCP.toolSearchDocsDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.MCP.schemaParamQuery]
                )
            ),
            Tool(
                name: Shared.Constants.MCP.toolListFrameworks,
                description: Shared.Constants.MCP.toolListFrameworksDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: [:],
                    required: []
                )
            ),
            Tool(
                name: Shared.Constants.MCP.toolReadDocument,
                description: Shared.Constants.MCP.toolReadDocumentDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.MCP.schemaParamURI]
                )
            ),
            Tool(
                name: Shared.Constants.MCP.toolSearchHIG,
                description: Shared.Constants.MCP.toolSearchHIGDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.MCP.schemaParamQuery]
                )
            ),
        ]

        return ListToolsResult(tools: tools)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        let args = ArgumentExtractor(arguments)

        switch name {
        case Shared.Constants.MCP.toolSearchDocs:
            return try await handleSearchDocs(args: args)
        case Shared.Constants.MCP.toolListFrameworks:
            return try await handleListFrameworks()
        case Shared.Constants.MCP.toolReadDocument:
            return try await handleReadDocument(args: args)
        case Shared.Constants.MCP.toolSearchHIG:
            return try await handleSearchHIG(args: args)
        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Tool Handlers

    private func handleSearchDocs(args: ArgumentExtractor) async throws -> CallToolResult {
        let query: String = try args.require(Shared.Constants.MCP.schemaParamQuery)
        let source = args.optional(Shared.Constants.MCP.schemaParamSource)
        let framework = args.optional(Shared.Constants.MCP.schemaParamFramework)
        let language = args.optional(Shared.Constants.MCP.schemaParamLanguage)
        let limit = args.limit()
        let includeArchive = args.includeArchive()

        // Perform search
        // Archive documentation is excluded by default unless include_archive=true or source=apple-archive
        let results = try await searchIndex.search(
            query: query,
            source: source,
            framework: framework,
            language: language,
            limit: limit,
            includeArchive: includeArchive
        )

        // Format results as markdown
        var markdown = "# Search Results for \"\(query)\"\n\n"

        if let source {
            markdown += "_Filtered to source: **\(source)**_\n\n"
        }
        if let framework {
            markdown += "_Filtered to framework: **\(framework)**_\n\n"
        }
        if let language {
            markdown += "_Filtered to language: **\(language)**_\n\n"
        }

        markdown += "Found **\(results.count)** result\(results.count == 1 ? "" : "s"):\n\n"

        if results.isEmpty {
            markdown += Shared.Constants.MCP.messageNoResults
        } else {
            for (index, result) in results.enumerated() {
                markdown += "## \(index + 1). \(result.title)\n\n"
                markdown += "- **Framework:** `\(result.framework)`\n"
                markdown += "- **URI:** `\(result.uri)`\n"
                markdown += "- **Score:** \(String(format: Shared.Constants.MCP.formatScore, result.score))\n"
                markdown += "- **Words:** \(result.wordCount)\n\n"

                // Add summary
                markdown += result.summary
                markdown += "\n\n"

                // Add separator except for last item
                if index < results.count - 1 {
                    markdown += "---\n\n"
                }
            }

            markdown += "\n\n"
            markdown += Shared.Constants.MCP.tipUseResourcesRead
            markdown += "\n"
        }

        let content = ContentBlock.text(
            TextContent(text: markdown)
        )

        return CallToolResult(content: [content])
    }

    private func handleListFrameworks() async throws -> CallToolResult {
        let frameworks = try await searchIndex.listFrameworks()
        let totalDocs = try await searchIndex.documentCount()

        var markdown = "# Available Frameworks\n\n"
        markdown += "Total documents: **\(totalDocs)**\n\n"

        if frameworks.isEmpty {
            let cmd = "\(Shared.Constants.App.commandName) \(Shared.Constants.Command.buildIndex)"
            markdown += Shared.Constants.MCP.messageNoFrameworks(buildIndexCommand: cmd)
        } else {
            markdown += "| Framework | Documents |\n"
            markdown += "|-----------|----------:|\n"

            // Sort by document count (descending)
            for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
                markdown += "| `\(framework)` | \(count) |\n"
            }

            markdown += "\n"
            markdown += Shared.Constants.MCP.tipFilterByFramework
            markdown += "\n"
        }

        let content = ContentBlock.text(
            TextContent(text: markdown)
        )

        return CallToolResult(content: [content])
    }

    private func handleReadDocument(args: ArgumentExtractor) async throws -> CallToolResult {
        let uri: String = try args.require(Shared.Constants.MCP.schemaParamURI)
        let formatString = args.format()
        let format: Search.Index.DocumentFormat = formatString == Shared.Constants.MCP.formatValueMarkdown
            ? .markdown : .json

        // Get document content from search index
        guard let documentContent = try await searchIndex.getDocumentContent(uri: uri, format: format) else {
            throw ToolError.invalidArgument(
                Shared.Constants.MCP.schemaParamURI,
                "Document not found: \(uri)"
            )
        }

        let content = ContentBlock.text(
            TextContent(text: documentContent)
        )

        return CallToolResult(content: [content])
    }

    private func handleSearchHIG(args: ArgumentExtractor) async throws -> CallToolResult {
        let query: String = try args.require(Shared.Constants.MCP.schemaParamQuery)
        let platform = args.optional(Shared.Constants.MCP.schemaParamPlatform)
        let category = args.optional(Shared.Constants.MCP.schemaParamCategory)
        let limit = args.limit()

        // Build HIG-specific query with optional platform/category filters
        var effectiveQuery = query
        if let platform {
            effectiveQuery += " \(platform)"
        }
        if let category {
            effectiveQuery += " \(category)"
        }

        // Search HIG content only (source pre-set to "hig")
        let results = try await searchIndex.search(
            query: effectiveQuery,
            source: Shared.Constants.SourcePrefix.hig,
            framework: nil,
            language: nil,
            limit: limit,
            includeArchive: false
        )

        // Format results as markdown
        var markdown = "# HIG Search Results for \"\(query)\"\n\n"

        if let platform {
            markdown += "_Platform: **\(platform)**_\n\n"
        }
        if let category {
            markdown += "_Category: **\(category)**_\n\n"
        }

        markdown += "Found **\(results.count)** guideline\(results.count == 1 ? "" : "s"):\n\n"

        if results.isEmpty {
            markdown += "_No Human Interface Guidelines found matching your query._\n\n"
            markdown += "**Tips:**\n"
            markdown += "- Try broader design terms (e.g., 'buttons', 'typography', 'navigation')\n"
            markdown += "- Specify a platform: iOS, macOS, watchOS, visionOS, tvOS\n"
            markdown += "- Specify a category: foundations, patterns, components, technologies, inputs\n"
        } else {
            for (index, result) in results.enumerated() {
                markdown += "## \(index + 1). \(result.title)\n\n"
                markdown += "- **URI:** `\(result.uri)`\n"
                markdown += "- **Score:** \(String(format: Shared.Constants.MCP.formatScore, result.score))\n\n"

                // Add summary
                markdown += result.summary
                markdown += "\n\n"

                // Add separator except for last item
                if index < results.count - 1 {
                    markdown += "---\n\n"
                }
            }

            markdown += "\n\n"
            markdown += Shared.Constants.MCP.tipUseResourcesRead
            markdown += "\n"
        }

        let content = ContentBlock.text(
            TextContent(text: markdown)
        )

        return CallToolResult(content: [content])
    }
}
