import Foundation

// MARK: - Prompts

/// A prompt that can be retrieved by the client
public struct Prompt: Codable, Sendable {
    public let name: String
    public let description: String?
    public let arguments: [PromptArgument]?

    public init(
        name: String,
        description: String? = nil,
        arguments: [PromptArgument]? = nil
    ) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }
}

/// Argument definition for a prompt
public struct PromptArgument: Codable, Sendable {
    public let name: String
    public let description: String?
    public let required: Bool?

    public init(
        name: String,
        description: String? = nil,
        required: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.required = required
    }
}

/// A message in a prompt (user or assistant role)
public struct PromptMessage: Codable, Sendable {
    public let role: Role
    public let content: ContentBlock

    public init(role: Role, content: ContentBlock) {
        self.role = role
        self.content = content
    }

    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }
}

// MARK: - Prompt Requests/Responses

/// List all available prompts
public struct ListPromptsRequest: Codable, Sendable {
    public let method: String = "prompts/list"
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

public struct ListPromptsResult: Codable, Sendable {
    public let prompts: [Prompt]
    public let nextCursor: String?

    public init(prompts: [Prompt], nextCursor: String? = nil) {
        self.prompts = prompts
        self.nextCursor = nextCursor
    }
}

/// Get a specific prompt
public struct GetPromptRequest: Codable, Sendable {
    public let method: String = "prompts/get"
    public let params: Params

    enum CodingKeys: String, CodingKey {
        case params
    }

    public init(name: String, arguments: [String: String]? = nil) {
        params = Params(name: name, arguments: arguments)
    }

    public struct Params: Codable, Sendable {
        public let name: String
        public let arguments: [String: String]?

        public init(name: String, arguments: [String: String]? = nil) {
            self.name = name
            self.arguments = arguments
        }
    }
}

public struct GetPromptResult: Codable, Sendable {
    public let description: String?
    public let messages: [PromptMessage]

    public init(description: String? = nil, messages: [PromptMessage]) {
        self.description = description
        self.messages = messages
    }
}

/// Prompt list changed notification (server → client)
public struct PromptListChangedNotification: Codable, Sendable {
    public let method: String = "notifications/prompts/list_changed"

    enum CodingKeys: String, CodingKey {
        case method
    }

    public init() {}
}
