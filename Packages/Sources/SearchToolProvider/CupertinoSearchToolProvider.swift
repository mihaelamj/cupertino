import Foundation
import MCP
import Search
import Shared

// MARK: - Documentation Search Tool Provider

/// Provides search tools for MCP clients to query documentation
public actor CupertinoSearchToolProvider: ToolProvider {
    private let searchIndex: SearchIndex

    public init(searchIndex: SearchIndex) {
        self.searchIndex = searchIndex
    }

    // MARK: - ToolProvider

    public func listTools(cursor: String?) async throws -> ListToolsResult {
        let tools = [
            Tool(
                name: CupertinoConstants.MCP.toolSearchDocs,
                description: CupertinoConstants.MCP.toolSearchDocsDescription,
                inputSchema: JSONSchema(
                    type: CupertinoConstants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [CupertinoConstants.MCP.schemaParamQuery]
                )
            ),
            Tool(
                name: CupertinoConstants.MCP.toolListFrameworks,
                description: CupertinoConstants.MCP.toolListFrameworksDescription,
                inputSchema: JSONSchema(
                    type: CupertinoConstants.MCP.schemaTypeObject,
                    properties: [:],
                    required: []
                )
            ),
        ]

        return ListToolsResult(tools: tools)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        switch name {
        case CupertinoConstants.MCP.toolSearchDocs:
            return try await handleSearchDocs(arguments: arguments)
        case CupertinoConstants.MCP.toolListFrameworks:
            return try await handleListFrameworks()
        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Tool Handlers

    private func handleSearchDocs(arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        guard let query = arguments?[CupertinoConstants.MCP.schemaParamQuery]?.value as? String else {
            throw ToolError.missingArgument(CupertinoConstants.MCP.schemaParamQuery)
        }

        let framework = arguments?[CupertinoConstants.MCP.schemaParamFramework]?.value as? String
        let defaultLimit = CupertinoConstants.Limit.defaultSearchLimit
        let requestedLimit = (arguments?[CupertinoConstants.MCP.schemaParamLimit]?.value as? Int) ?? defaultLimit
        let limit = min(requestedLimit, CupertinoConstants.Limit.maxSearchLimit)

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
            markdown += CupertinoConstants.MCP.messageNoResults
        } else {
            for (index, result) in results.enumerated() {
                markdown += "## \(index + 1). \(result.title)\n\n"
                markdown += "- **Framework:** `\(result.framework)`\n"
                markdown += "- **URI:** `\(result.uri)`\n"
                markdown += "- **Score:** \(String(format: CupertinoConstants.MCP.formatScore, result.score))\n"
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
            markdown += CupertinoConstants.MCP.tipUseResourcesRead
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
            let cmd = "\(CupertinoConstants.App.commandName) \(CupertinoConstants.Command.buildIndex)"
            markdown += CupertinoConstants.MCP.messageNoFrameworks(buildIndexCommand: cmd)
        } else {
            markdown += "| Framework | Documents |\n"
            markdown += "|-----------|----------:|\n"

            // Sort by document count (descending)
            for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
                markdown += "| `\(framework)` | \(count) |\n"
            }

            markdown += "\n"
            markdown += CupertinoConstants.MCP.tipFilterByFramework
            markdown += "\n"
        }

        let content = ContentBlock.text(
            TextContent(text: markdown)
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
