import CupertinoSearch
import Foundation
import MCPServer
import MCPShared

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
                name: "search_docs",
                description: """
                Search Apple documentation and Swift Evolution proposals by keywords. \
                Returns a ranked list of relevant documents with URIs that can be read using resources/read.
                """,
                inputSchema: JSONSchema(
                    type: "object",
                    properties: nil,
                    required: ["query"]
                )
            ),
            Tool(
                name: "list_frameworks",
                description: """
                List all available frameworks in the documentation index with document counts. \
                Useful for discovering what documentation is available.
                """,
                inputSchema: JSONSchema(
                    type: "object",
                    properties: [:],
                    required: []
                )
            ),
        ]

        return ListToolsResult(tools: tools)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        switch name {
        case "search_docs":
            return try await handleSearchDocs(arguments: arguments)
        case "list_frameworks":
            return try await handleListFrameworks()
        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Tool Handlers

    private func handleSearchDocs(arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        guard let query = arguments?["query"]?.value as? String else {
            throw ToolError.missingArgument("query")
        }

        let framework = arguments?["framework"]?.value as? String
        let limit = min((arguments?["limit"]?.value as? Int) ?? 20, 100)

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
            markdown += """
            _No results found. Try different keywords or check available frameworks using `list_frameworks`._
            """
        } else {
            for (index, result) in results.enumerated() {
                markdown += "## \(index + 1). \(result.title)\n\n"
                markdown += "- **Framework:** `\(result.framework)`\n"
                markdown += "- **URI:** `\(result.uri)`\n"
                markdown += "- **Score:** \(String(format: "%.2f", result.score))\n"
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
            markdown += "💡 **Tip:** Use `resources/read` with the URI to get the full document content.\n"
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
            markdown += """
            _No frameworks found. The search index may be empty. \
            Run `cupertino build-index` to index your documentation._
            """
        } else {
            markdown += "| Framework | Documents |\n"
            markdown += "|-----------|----------:|\n"

            // Sort by document count (descending)
            for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
                markdown += "| `\(framework)` | \(count) |\n"
            }

            markdown += "\n"
            markdown += "💡 **Tip:** Use `search_docs` with the `framework` parameter to filter results.\n"
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
