import Foundation
import MCP
import Search
import Shared

// MARK: - Documentation Search Tool Provider

/// Provides search tools for MCP clients to query documentation
public actor CupertinoSearchToolProvider: ToolProvider {
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
        ]

        return ListToolsResult(tools: tools)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        switch name {
        case Shared.Constants.MCP.toolSearchDocs:
            return try await handleSearchDocs(arguments: arguments)
        case Shared.Constants.MCP.toolListFrameworks:
            return try await handleListFrameworks()
        case Shared.Constants.MCP.toolReadDocument:
            return try await handleReadDocument(arguments: arguments)
        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Tool Handlers

    private func handleSearchDocs(arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        guard let query = arguments?[Shared.Constants.MCP.schemaParamQuery]?.value as? String else {
            throw ToolError.missingArgument(Shared.Constants.MCP.schemaParamQuery)
        }

        let framework = arguments?[Shared.Constants.MCP.schemaParamFramework]?.value as? String
        let defaultLimit = Shared.Constants.Limit.defaultSearchLimit
        let requestedLimit = (arguments?[Shared.Constants.MCP.schemaParamLimit]?.value as? Int) ?? defaultLimit
        let limit = min(requestedLimit, Shared.Constants.Limit.maxSearchLimit)

        // Perform search
        let results = try await searchIndex.search(
            query: query,
            framework: framework,
            limit: limit
        )

        // Format results as markdown
        var markdown = "# Search Results for \"\(query)\"\n\n"

        if let framework {
            markdown += "_Filtered to framework: **\(framework)**_\n\n"
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

    private func handleReadDocument(arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        guard let uri = arguments?[Shared.Constants.MCP.schemaParamURI]?.value as? String else {
            throw ToolError.missingArgument(Shared.Constants.MCP.schemaParamURI)
        }

        // Parse format parameter (default: json)
        let formatString = (arguments?[Shared.Constants.MCP.schemaParamFormat]?.value as? String)
            ?? Shared.Constants.MCP.formatValueJSON
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
}

// MARK: - Tool Errors

enum ToolError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String, String) // argument name, reason

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .missingArgument(let arg):
            return "Missing required argument: \(arg)"
        case .invalidArgument(let arg, let reason):
            return "Invalid argument '\(arg)': \(reason)"
        }
    }
}
