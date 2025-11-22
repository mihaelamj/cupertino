import Foundation

// MARK: - Tools

/// A tool that can be called by the client
public struct Tool: Codable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONSchema

    public init(
        name: String,
        description: String? = nil,
        inputSchema: JSONSchema
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// JSON Schema for tool input validation
public struct JSONSchema: Codable, Sendable {
    public let type: String
    public let properties: [String: AnyCodable]?
    public let required: [String]?

    public init(
        type: String = "object",
        properties: [String: AnyCodable]? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

// MARK: - Tool Requests/Responses

/// List all available tools
public struct ListToolsRequest: Codable, Sendable {
    public let method: String = MCPMethod.toolsList
    public let params: Params?

    enum CodingKeys: String, CodingKey {
        case params
    }

    public init(cursor: String? = nil) {
        params = cursor.map { Params(cursor: $0) }
    }

    public struct Params: Codable, Sendable {
        public let cursor: String

        public init(cursor: String) {
            self.cursor = cursor
        }
    }
}

public struct ListToolsResult: Codable, Sendable {
    public let tools: [Tool]
    public let nextCursor: String?

    public init(tools: [Tool], nextCursor: String? = nil) {
        self.tools = tools
        self.nextCursor = nextCursor
    }
}

/// Call a tool
public struct CallToolRequest: Codable, Sendable {
    public let method: String = MCPMethod.toolsCall
    public let params: Params

    enum CodingKeys: String, CodingKey {
        case params
    }

    public init(name: String, arguments: [String: AnyCodable]? = nil) {
        params = Params(name: name, arguments: arguments)
    }

    public struct Params: Codable, Sendable {
        public let name: String
        public let arguments: [String: AnyCodable]?

        public init(name: String, arguments: [String: AnyCodable]? = nil) {
            self.name = name
            self.arguments = arguments
        }
    }
}

public struct CallToolResult: Codable, Sendable {
    public let content: [ContentBlock]
    public let isError: Bool?

    public init(content: [ContentBlock], isError: Bool? = nil) {
        self.content = content
        self.isError = isError
    }
}

/// Tool list changed notification (server → client)
public struct ToolListChangedNotification: Codable, Sendable {
    public let method: String = MCPMethod.notificationsToolsListChanged

    enum CodingKeys: String, CodingKey {
        case method
    }

    public init() {}
}

// MARK: - Type Aliases

public typealias CallToolParams = CallToolRequest.Params
