import Foundation
import MCP
import SampleIndex
import Shared

// MARK: - Sample Code Search Tool Provider

/// Provides sample code search tools for MCP clients
public actor SampleCodeToolProvider: ToolProvider {
    private let database: SampleIndex.Database

    public init(database: SampleIndex.Database) {
        self.database = database
    }

    // MARK: - ToolProvider

    public func listTools(cursor: String?) async throws -> ListToolsResult {
        let tools = [
            Tool(
                name: Shared.Constants.MCP.toolSearchSamples,
                description: Shared.Constants.MCP.toolSearchSamplesDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.MCP.schemaParamQuery]
                )
            ),
            Tool(
                name: Shared.Constants.MCP.toolListSamples,
                description: Shared.Constants.MCP.toolListSamplesDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: [:],
                    required: []
                )
            ),
            Tool(
                name: Shared.Constants.MCP.toolReadSample,
                description: Shared.Constants.MCP.toolReadSampleDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [Shared.Constants.MCP.schemaParamProjectId]
                )
            ),
            Tool(
                name: Shared.Constants.MCP.toolReadSampleFile,
                description: Shared.Constants.MCP.toolReadSampleFileDescription,
                inputSchema: JSONSchema(
                    type: Shared.Constants.MCP.schemaTypeObject,
                    properties: nil,
                    required: [
                        Shared.Constants.MCP.schemaParamProjectId,
                        Shared.Constants.MCP.schemaParamFilePath,
                    ]
                )
            ),
        ]

        return ListToolsResult(tools: tools)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        let args = ArgumentExtractor(arguments)

        switch name {
        case Shared.Constants.MCP.toolSearchSamples:
            return try await handleSearchSamples(args: args)
        case Shared.Constants.MCP.toolListSamples:
            return try await handleListSamples(args: args)
        case Shared.Constants.MCP.toolReadSample:
            return try await handleReadSample(args: args)
        case Shared.Constants.MCP.toolReadSampleFile:
            return try await handleReadSampleFile(args: args)
        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Tool Handlers

    private func handleSearchSamples(args: ArgumentExtractor) async throws -> CallToolResult {
        let query: String = try args.require(Shared.Constants.MCP.schemaParamQuery)
        let framework = args.optional(Shared.Constants.MCP.schemaParamFramework)
        let limit = args.limit()
        let searchFiles = args.optional(Shared.Constants.MCP.schemaParamSearchFiles, default: true)

        // Search projects
        let projects = try await database.searchProjects(query: query, framework: framework, limit: limit)

        // Optionally search files
        var files: [SampleIndex.Database.FileSearchResult] = []
        if searchFiles {
            files = try await database.searchFiles(query: query, projectId: nil, limit: limit)
        }

        // Format results
        var markdown = "# Sample Code Search: \"\(query)\"\n\n"

        if let framework {
            markdown += "_Filtered to framework: **\(framework)**_\n\n"
        }

        // Projects section
        markdown += "## Projects (\(projects.count) found)\n\n"

        if projects.isEmpty {
            markdown += "_No matching projects found._\n\n"
        } else {
            for (index, project) in projects.enumerated() {
                markdown += "### \(index + 1). \(project.title)\n\n"
                markdown += "- **ID:** `\(project.id)`\n"
                markdown += "- **Framework:** `\(project.frameworks.joined(separator: ", "))`\n"
                markdown += "- **Files:** \(project.fileCount)\n\n"

                if !project.description.isEmpty {
                    markdown += project.description + "\n\n"
                }

                if index < projects.count - 1 {
                    markdown += "---\n\n"
                }
            }
        }

        // Files section
        if searchFiles, !files.isEmpty {
            markdown += "\n## Matching Files (\(files.count) found)\n\n"

            for (index, result) in files.prefix(10).enumerated() {
                markdown += "### \(index + 1). \(result.filename)\n\n"
                markdown += "- **Project:** `\(result.projectId)`\n"
                markdown += "- **Path:** `\(result.path)`\n"
                markdown += "- **Score:** \(String(format: "%.2f", result.rank))\n\n"

                // Show snippet of content
                let snippet = result.snippet
                    .replacingOccurrences(of: "\n", with: "\n> ")
                markdown += "> \(snippet)\n\n"

                if index < min(files.count, 10) - 1 {
                    markdown += "---\n\n"
                }
            }
        }

        markdown += "\n\n"
        markdown += "💡 **Tip:** Use `read_sample` with project_id to see full README, or `read_sample_file` to view source code."
        markdown += "\n"

        let content = ContentBlock.text(TextContent(text: markdown))
        return CallToolResult(content: [content])
    }

    private func handleListSamples(args: ArgumentExtractor) async throws -> CallToolResult {
        let framework = args.optional(Shared.Constants.MCP.schemaParamFramework)
        let limit = args.limit(default: 50)

        let projects = try await database.listProjects(framework: framework, limit: limit)
        let totalProjects = try await database.projectCount()
        let totalFiles = try await database.fileCount()

        var markdown = "# Indexed Sample Code Projects\n\n"
        markdown += "Total projects: **\(totalProjects)**\n"
        markdown += "Total files: **\(totalFiles)**\n\n"

        if let framework {
            markdown += "_Filtered to framework: **\(framework)**_\n\n"
        }

        if projects.isEmpty {
            markdown += "_No projects found. Run `cupertino index` to index sample code._\n"
        } else {
            markdown += "| Project | Framework | Files |\n"
            markdown += "|---------|-----------|------:|\n"

            for project in projects {
                let frameworks = project.frameworks.joined(separator: ", ")
                markdown += "| `\(project.id)` | \(frameworks) | \(project.fileCount) |\n"
            }

            markdown += "\n"
            markdown += "💡 **Tip:** Use `search_samples` to find projects by keyword, or `read_sample` to view project details."
            markdown += "\n"
        }

        let content = ContentBlock.text(TextContent(text: markdown))
        return CallToolResult(content: [content])
    }

    private func handleReadSample(args: ArgumentExtractor) async throws -> CallToolResult {
        let projectId: String = try args.require(Shared.Constants.MCP.schemaParamProjectId)

        guard let project = try await database.getProject(id: projectId) else {
            throw ToolError.invalidArgument(
                Shared.Constants.MCP.schemaParamProjectId,
                "Project not found: \(projectId)"
            )
        }

        var markdown = "# \(project.title)\n\n"
        markdown += "**Project ID:** `\(project.id)`\n\n"

        if !project.description.isEmpty {
            markdown += "## Description\n\n"
            markdown += project.description + "\n\n"
        }

        markdown += "## Metadata\n\n"
        markdown += "- **Frameworks:** \(project.frameworks.joined(separator: ", "))\n"
        markdown += "- **Files:** \(project.fileCount)\n"
        markdown += "- **Size:** \(formatBytes(project.totalSize))\n"
        if !project.webURL.isEmpty {
            markdown += "- **Apple Developer:** \(project.webURL)\n"
        }
        markdown += "\n"

        if let readme = project.readme, !readme.isEmpty {
            markdown += "## README\n\n"
            markdown += readme
            markdown += "\n\n"
        }

        // List some files
        let files = try await database.listFiles(projectId: projectId)
        if !files.isEmpty {
            markdown += "## Files (\(files.count) total)\n\n"
            for file in files.prefix(30) {
                markdown += "- `\(file.path)`\n"
            }
            if files.count > 30 {
                markdown += "- _... and \(files.count - 30) more files_\n"
            }
            markdown += "\n"
            markdown += "💡 Use `read_sample_file` with project_id and file_path to view source code.\n"
        }

        let content = ContentBlock.text(TextContent(text: markdown))
        return CallToolResult(content: [content])
    }

    private func handleReadSampleFile(args: ArgumentExtractor) async throws -> CallToolResult {
        let projectId: String = try args.require(Shared.Constants.MCP.schemaParamProjectId)
        let filePath: String = try args.require(Shared.Constants.MCP.schemaParamFilePath)

        guard let file = try await database.getFile(projectId: projectId, path: filePath) else {
            throw ToolError.invalidArgument(
                Shared.Constants.MCP.schemaParamFilePath,
                "File not found: \(filePath) in project \(projectId)"
            )
        }

        var markdown = "# \(file.filename)\n\n"
        markdown += "**Project:** `\(file.projectId)`\n"
        markdown += "**Path:** `\(file.path)`\n"
        markdown += "**Size:** \(formatBytes(file.size))\n\n"

        // Determine language for syntax highlighting
        let language = languageForExtension(file.fileExtension)

        markdown += "```\(language)\n"
        markdown += file.content
        if !file.content.hasSuffix("\n") {
            markdown += "\n"
        }
        markdown += "```\n"

        let content = ContentBlock.text(TextContent(text: markdown))
        return CallToolResult(content: [content])
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func languageForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "h", "m", "mm": return "objc"
        case "c": return "c"
        case "cpp", "hpp": return "cpp"
        case "metal": return "metal"
        case "json": return "json"
        case "plist": return "xml"
        case "md": return "markdown"
        case "strings": return "properties"
        default: return ext
        }
    }
}
