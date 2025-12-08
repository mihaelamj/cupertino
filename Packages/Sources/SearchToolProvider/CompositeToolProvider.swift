import Foundation
import MCP
import SampleIndex
import Search
import Shared

// MARK: - Unified Cupertino Tool Provider

/// Composite tool provider that delegates to both documentation and sample code providers
public actor CompositeToolProvider: ToolProvider {
    private let documentationTools: DocumentationToolProvider?
    private let sampleCodeTools: SampleCodeToolProvider?

    public init(searchIndex: Search.Index?, sampleDatabase: SampleIndex.Database?) {
        documentationTools = searchIndex.map { DocumentationToolProvider(searchIndex: $0) }
        sampleCodeTools = sampleDatabase.map { SampleCodeToolProvider(database: $0) }
    }

    // MARK: - ToolProvider

    public func listTools(cursor: String?) async throws -> ListToolsResult {
        var allTools: [Tool] = []

        // Get tools from documentation provider
        if let documentationTools {
            let docTools = try await documentationTools.listTools(cursor: cursor)
            allTools.append(contentsOf: docTools.tools)
        }

        // Get tools from sample code provider
        if let sampleCodeTools {
            let sampleTools = try await sampleCodeTools.listTools(cursor: cursor)
            allTools.append(contentsOf: sampleTools.tools)
        }

        return ListToolsResult(tools: allTools)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        // Try documentation provider first
        if let documentationTools {
            let docTools = try await documentationTools.listTools(cursor: nil)
            if docTools.tools.contains(where: { $0.name == name }) {
                return try await documentationTools.callTool(name: name, arguments: arguments)
            }
        }

        // Try sample code provider next
        if let sampleCodeTools {
            let sampleTools = try await sampleCodeTools.listTools(cursor: nil)
            if sampleTools.tools.contains(where: { $0.name == name }) {
                return try await sampleCodeTools.callTool(name: name, arguments: arguments)
            }
        }

        // Tool not found in any provider
        throw ToolError.unknownTool(name)
    }
}
