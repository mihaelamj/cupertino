import Foundation
import MCPShared

// MARK: - Resource Provider

/// Protocol for types that provide MCP resources
public protocol ResourceProvider: Sendable {
    /// List all available resources
    func listResources(cursor: String?) async throws -> ListResourcesResult

    /// Read a specific resource by URI
    func readResource(uri: String) async throws -> ReadResourceResult

    /// Optional: List resource templates with URI patterns
    func listResourceTemplates(cursor: String?) async throws -> ListResourceTemplatesResult?
}

// Default implementation for templates (returns nil if not implemented)
extension ResourceProvider {
    public func listResourceTemplates(cursor: String?) async throws -> ListResourceTemplatesResult? {
        nil
    }
}

// MARK: - Tool Provider

/// Protocol for types that provide MCP tools
public protocol ToolProvider: Sendable {
    /// List all available tools
    func listTools(cursor: String?) async throws -> ListToolsResult

    /// Call a specific tool
    func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult
}

// MARK: - Prompt Provider

/// Protocol for types that provide MCP prompts
public protocol PromptProvider: Sendable {
    /// List all available prompts
    func listPrompts(cursor: String?) async throws -> ListPromptsResult

    /// Get a specific prompt
    func getPrompt(name: String, arguments: [String: String]?) async throws -> GetPromptResult
}

// MARK: - Capability Detection

/// Helper to detect which capabilities a provider supports
public struct ProviderCapabilities: Sendable {
    public let hasResources: Bool
    public let hasResourceTemplates: Bool
    public let hasTools: Bool
    public let hasPrompts: Bool

    public init(
        hasResources: Bool = false,
        hasResourceTemplates: Bool = false,
        hasTools: Bool = false,
        hasPrompts: Bool = false
    ) {
        self.hasResources = hasResources
        self.hasResourceTemplates = hasResourceTemplates
        self.hasTools = hasTools
        self.hasPrompts = hasPrompts
    }

    /// Create capabilities from registered providers
    public static func from(
        resourceProvider: (any ResourceProvider)?,
        toolProvider: (any ToolProvider)?,
        promptProvider: (any PromptProvider)?
    ) -> ProviderCapabilities {
        ProviderCapabilities(
            hasResources: resourceProvider != nil,
            hasResourceTemplates: false, // Can be detected at runtime
            hasTools: toolProvider != nil,
            hasPrompts: promptProvider != nil
        )
    }

    /// Convert to MCP ServerCapabilities
    public func toServerCapabilities() -> ServerCapabilities {
        ServerCapabilities(
            logging: nil,
            prompts: hasPrompts ? ServerCapabilities.PromptsCapability(listChanged: false) : nil,
            resources: hasResources ? ServerCapabilities.ResourcesCapability(
                subscribe: false,
                listChanged: false
            ) : nil,
            tools: hasTools ? ServerCapabilities.ToolsCapability(listChanged: false) : nil
        )
    }
}
