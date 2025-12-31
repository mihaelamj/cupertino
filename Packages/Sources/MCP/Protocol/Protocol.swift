import Foundation

// MARK: - MCP Protocol Version

public let MCPProtocolVersion = "2025-06-18"
public let MCPProtocolVersionsSupported = [
    MCPProtocolVersion,
    "2024-11-05",
]

// MARK: - Implementation Info

public struct Implementation: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

// MARK: - Initialization

public struct ClientCapabilities: Codable, Sendable {
    public let experimental: [String: AnyCodable]?
    public let sampling: SamplingCapability?
    public let roots: RootsCapability?

    public init(
        experimental: [String: AnyCodable]? = nil,
        sampling: SamplingCapability? = nil,
        roots: RootsCapability? = nil
    ) {
        self.experimental = experimental
        self.sampling = sampling
        self.roots = roots
    }

    public struct SamplingCapability: Codable, Sendable {
        public init() {}
    }

    public struct RootsCapability: Codable, Sendable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }
}

public struct ServerCapabilities: Codable, Sendable {
    public let experimental: [String: AnyCodable]?
    public let logging: LoggingCapability?
    public let prompts: PromptsCapability?
    public let resources: ResourcesCapability?
    public let tools: ToolsCapability?

    public init(
        experimental: [String: AnyCodable]? = nil,
        logging: LoggingCapability? = nil,
        prompts: PromptsCapability? = nil,
        resources: ResourcesCapability? = nil,
        tools: ToolsCapability? = nil
    ) {
        self.experimental = experimental
        self.logging = logging
        self.prompts = prompts
        self.resources = resources
        self.tools = tools
    }

    public struct LoggingCapability: Codable, Sendable {
        public init() {}
    }

    public struct PromptsCapability: Codable, Sendable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    public struct ResourcesCapability: Codable, Sendable {
        public let subscribe: Bool?
        public let listChanged: Bool?

        public init(subscribe: Bool? = nil, listChanged: Bool? = nil) {
            self.subscribe = subscribe
            self.listChanged = listChanged
        }
    }

    public struct ToolsCapability: Codable, Sendable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }
}

public struct InitializeRequest: Codable, Sendable {
    public let method: String = MCPMethod.initialize
    public let params: Params

    enum CodingKeys: String, CodingKey {
        case params
    }

    public init(
        protocolVersion: String,
        capabilities: ClientCapabilities,
        clientInfo: Implementation
    ) {
        params = Params(
            protocolVersion: protocolVersion,
            capabilities: capabilities,
            clientInfo: clientInfo
        )
    }

    public struct Params: Codable, Sendable {
        public let protocolVersion: String
        public let capabilities: ClientCapabilities
        public let clientInfo: Implementation

        public init(
            protocolVersion: String,
            capabilities: ClientCapabilities,
            clientInfo: Implementation
        ) {
            self.protocolVersion = protocolVersion
            self.capabilities = capabilities
            self.clientInfo = clientInfo
        }
    }
}

public struct InitializeResult: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: ServerCapabilities
    public let serverInfo: Implementation
    public let instructions: String?

    public init(
        protocolVersion: String,
        capabilities: ServerCapabilities,
        serverInfo: Implementation,
        instructions: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
        self.instructions = instructions
    }
}

// MARK: - Type Aliases for Client Use

public typealias InitializeParams = InitializeRequest.Params
public typealias RootsCapability = ClientCapabilities.RootsCapability
