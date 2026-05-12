import Foundation

// MARK: - MCP.Core.Protocols.Resource Provider

/// Protocol for types that provide MCP resources
extension MCP.Core {
    public protocol ResourceProvider: Sendable {
        /// List all available resources
        func listResources(cursor: String?) async throws -> MCP.Core.Protocols.ListResourcesResult

        /// Read a specific resource by URI
        func readResource(uri: String) async throws -> MCP.Core.Protocols.ReadResourceResult

        /// Optional: List resource templates with URI patterns
        func listResourceTemplates(cursor: String?) async throws -> MCP.Core.Protocols.ListResourceTemplatesResult?
    }
}

/// Default implementation for templates (returns nil if not implemented)
extension MCP.Core.ResourceProvider {
    public func listResourceTemplates(cursor: String?) async throws -> MCP.Core.Protocols.ListResourceTemplatesResult? {
        nil
    }
}

// MARK: - MCP.Core.Protocols.Tool Provider

/// Protocol for types that provide MCP tools
extension MCP.Core {
    public protocol ToolProvider: Sendable {
        /// List all available tools
        func listTools(cursor: String?) async throws -> MCP.Core.Protocols.ListToolsResult

        /// Call a specific tool
        func callTool(name: String, arguments: [String: MCP.Core.Protocols.AnyCodable]?) async throws -> MCP.Core.Protocols.CallToolResult
    }
}

// MARK: - MCP.Core.Protocols.Prompt Provider

/// Protocol for types that provide MCP prompts
extension MCP.Core {
    public protocol PromptProvider: Sendable {
        /// List all available prompts
        func listPrompts(cursor: String?) async throws -> MCP.Core.Protocols.ListPromptsResult

        /// Get a specific prompt
        func getPrompt(name: String, arguments: [String: String]?) async throws -> MCP.Core.Protocols.GetPromptResult
    }
}

// MARK: - Capability Detection

/// Helper to detect which capabilities a provider supports
extension MCP.Core {
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

        /// Convert to MCP MCP.Core.Protocols.ServerCapabilities
        public func toServerCapabilities() -> MCP.Core.Protocols.ServerCapabilities {
            MCP.Core.Protocols.ServerCapabilities(
                logging: nil,
                prompts: hasPrompts ? MCP.Core.Protocols.ServerCapabilities.PromptsCapability(listChanged: false) : nil,
                resources: hasResources ? MCP.Core.Protocols.ServerCapabilities.ResourcesCapability(
                    subscribe: false,
                    listChanged: false
                ) : nil,
                tools: hasTools ? MCP.Core.Protocols.ServerCapabilities.ToolsCapability(listChanged: false) : nil
            )
        }
    }
}
