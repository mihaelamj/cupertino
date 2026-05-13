import Foundation
import MCPCore

// MARK: - Cupertino Convenience Methods

extension MCP.Client {
    /// Create an MCP client configured for the cupertino server
    /// - Parameter executablePath: Path to cupertino executable (defaults to searching in common locations)
    public static func cupertino(executablePath: String? = nil) -> MCP.Client {
        let path = executablePath ?? findCupertinoExecutable()
        return MCP.Client(serverCommand: path, serverArguments: ["serve"])
    }

    /// Search Apple documentation
    /// - Parameters:
    ///   - query: Search query
    ///   - limit: Maximum number of results (default: 10)
    /// - Returns: Search results as markdown text
    public func searchDocs(query: String, limit: Int = 10) async throws -> String {
        let result = try await callTool(name: "search_docs", arguments: [
            "query": MCP.Core.Protocols.AnyCodable(query),
            "limit": MCP.Core.Protocols.AnyCodable(limit),
        ])
        return extractText(from: result)
    }

    /// Search sample code projects
    /// - Parameters:
    ///   - query: Search query
    ///   - framework: Optional framework filter
    ///   - limit: Maximum number of results (default: 10)
    /// - Returns: Search results as markdown text
    public func searchSamples(query: String, framework: String? = nil, limit: Int = 10) async throws -> String {
        var args: [String: MCP.Core.Protocols.AnyCodable] = [
            "query": MCP.Core.Protocols.AnyCodable(query),
            "limit": MCP.Core.Protocols.AnyCodable(limit),
        ]
        if let framework {
            args["framework"] = MCP.Core.Protocols.AnyCodable(framework)
        }

        let result = try await callTool(name: "search_samples", arguments: args)
        return extractText(from: result)
    }

    /// List all indexed sample code projects
    /// - Parameters:
    ///   - framework: Optional framework filter
    ///   - limit: Maximum number of results (default: 50)
    /// - Returns: Project list as markdown text
    public func listSamples(framework: String? = nil, limit: Int = 50) async throws -> String {
        var args: [String: MCP.Core.Protocols.AnyCodable] = ["limit": MCP.Core.Protocols.AnyCodable(limit)]
        if let framework {
            args["framework"] = MCP.Core.Protocols.AnyCodable(framework)
        }

        let result = try await callTool(name: "list_samples", arguments: args)
        return extractText(from: result)
    }

    /// Read a sample code project's details
    /// - Parameter projectId: Project ID (e.g., "swiftui-fruta-sample")
    /// - Returns: Project details as markdown text
    public func readSample(projectId: String) async throws -> String {
        let result = try await callTool(name: "read_sample", arguments: [
            "project_id": MCP.Core.Protocols.AnyCodable(projectId),
        ])
        return extractText(from: result)
    }

    /// Read a specific file from a sample code project
    /// - Parameters:
    ///   - projectId: Project ID
    ///   - filePath: Path to file within the project
    /// - Returns: File contents with syntax highlighting
    public func readSampleFile(projectId: String, filePath: String) async throws -> String {
        let result = try await callTool(name: "read_sample_file", arguments: [
            "project_id": MCP.Core.Protocols.AnyCodable(projectId),
            "file_path": MCP.Core.Protocols.AnyCodable(filePath),
        ])
        return extractText(from: result)
    }

    /// Read a documentation resource by URI
    /// - Parameter uri: Resource URI (e.g., "apple-docs://swiftui/documentation_swiftui_view")
    /// - Returns: Documentation content as markdown
    public func readDocumentation(uri: String) async throws -> String {
        let result = try await readResource(uri: uri)

        var text = ""
        for content in result.contents {
            switch content {
            case .text(let textContent):
                text += textContent.text
            case .blob:
                break
            }
        }
        return text
    }

    // MARK: - Private Helpers

    private func extractText(from result: MCP.Core.Protocols.CallToolResult) -> String {
        var text = ""
        for content in result.content {
            switch content {
            case .text(let textContent):
                text += textContent.text
            case .image, .resource:
                break
            }
        }
        return text
    }

    private static func findCupertinoExecutable() -> String {
        let locations = [
            ".build/debug/cupertino",
            ".build/release/cupertino",
            "/usr/local/bin/cupertino",
            "/opt/homebrew/bin/cupertino",
        ]

        for location in locations where FileManager.default.fileExists(atPath: location) {
            return location
        }

        // Default to debug build
        return ".build/debug/cupertino"
    }
}
