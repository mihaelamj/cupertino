import Foundation

// MARK: - MCP Server

/// Main MCP server implementation
/// Handles initialization, request routing, and provider management
extension MCP.Core {
    public actor Server {
        // Server information
        private let serverInfo: MCP.Core.Protocols.Implementation
        private var capabilities: MCP.Core.Protocols.ServerCapabilities

        // Providers
        private var resourceProvider: (any ResourceProvider)?
        private var toolProvider: (any ToolProvider)?
        private var promptProvider: (any PromptProvider)?

        // Transport
        private var transport: (any MCP.Core.Transport.Channel)?
        private var messageTask: Task<Void, Never>?

        // State
        private var isInitialized = false
        private var isRunning = false
        private var requestID: Int = 0

        public init(name: String, version: String, icons: [MCP.Core.Protocols.Icon]? = nil) {
            serverInfo = MCP.Core.Protocols.Implementation(name: name, version: version, icons: icons)
            capabilities = MCP.Core.Protocols.ServerCapabilities()
        }

        // MARK: - Provider Registration

        /// Register a resource provider
        public func registerResourceProvider(_ provider: some ResourceProvider) {
            resourceProvider = provider
            updateCapabilities()
        }

        /// Register a tool provider
        public func registerToolProvider(_ provider: some ToolProvider) {
            toolProvider = provider
            updateCapabilities()
        }

        /// Register a prompt provider
        public func registerPromptProvider(_ provider: some PromptProvider) {
            promptProvider = provider
            updateCapabilities()
        }

        private func updateCapabilities() {
            let providerCaps = ProviderCapabilities.from(
                resourceProvider: resourceProvider,
                toolProvider: toolProvider,
                promptProvider: promptProvider
            )
            capabilities = providerCaps.toServerCapabilities()
        }

        // MARK: - Server Lifecycle

        /// Connect to a transport and start the server
        public func connect(_ transport: some MCP.Core.Transport.Channel) async throws {
            guard !isRunning else {
                throw ServerError.alreadyRunning
            }

            self.transport = transport

            // Start transport
            try await transport.start()

            // Start message processing loop
            messageTask = Task { [weak self] in
                await self?.processMessages()
            }

            isRunning = true
            logInfo("Server started and waiting for initialization")
        }

        /// Disconnect and stop the server
        public func disconnect() async throws {
            guard isRunning else {
                return
            }

            isRunning = false
            messageTask?.cancel()
            messageTask = nil

            try await transport?.stop()
            transport = nil

            logInfo("Server stopped")
        }

        // MARK: - MCP.Core.Transport.Message Processing

        private func processMessages() async {
            guard let transport else {
                return
            }

            let messageStream = await transport.messages
            for await message in messageStream {
                do {
                    try await handleMessage(message)
                } catch {
                    logError("Error handling message: \(error)")
                }
            }
        }

        private func handleMessage(_ message: MCP.Core.Transport.Message) async throws {
            switch message {
            case .request(let request):
                try await handleRequest(request)
            case .notification(let notification):
                try await handleNotification(notification)
            case .response, .error:
                // Servers don't typically receive responses
                logWarning("Received unexpected response/error message")
            }
        }

        private func handleRequest(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws {
            guard let transport else {
                throw ServerError.transportNotConnected
            }

            // #581: every id-bound request MUST receive either a `result`
            // or `error` response per JSON-RPC 2.0 + MCP 2025-06-18. Pre-
            // fix only `ServerError` was converted to a JSON-RPC error;
            // every other thrown error (notably the
            // `Shared.Core.ToolError.invalidArgument(...)` errors that
            // tool handlers like `read_document` raise for bad URIs) fell
            // through, got logged to stderr, and the client request hung
            // waiting for its id to come back. Now every catch emits a
            // typed JSON-RPC error frame; only un-categorised errors map
            // to `internalError`.
            do {
                let result = try await routeRequest(request)
                let response = MCP.Core.Protocols.JSONRPCResponse(id: request.id, result: result)
                try await transport.send(.response(response))
            } catch let error as ServerError {
                let errorResponse = MCP.Core.Protocols.JSONRPCError(
                    id: request.id,
                    error: MCP.Core.Protocols.JSONRPCError.ErrorDetail(
                        code: error.code,
                        message: error.message
                    )
                )
                try await transport.send(.error(errorResponse))
            } catch {
                // Catch-all for any non-ServerError thrown from
                // `routeRequest` (the typical case is a tool handler
                // raising `Shared.Core.ToolError.invalidArgument` for a
                // bad URI or missing required arg). Map to JSON-RPC
                // -32602 InvalidParams when the underlying error is
                // about argument shape; otherwise default to
                // -32603 InternalError.
                let detailCode = MCP.Core.Protocols.ErrorCode.invalidParams.rawValue
                let detailMessage: String
                let errorDescription = String(describing: error)
                // `Shared.Core.ToolError` emits `.invalidArgument(field, message)` and
                // `.invalidURI(uri)` shapes; surface those as InvalidParams
                // with a stable user-facing message. Anything else we
                // pass through verbatim so the client at least sees what
                // happened, rather than hanging.
                if let localized = error as? LocalizedError, let description = localized.errorDescription {
                    detailMessage = description
                } else {
                    detailMessage = errorDescription
                }
                logError("Error handling message (returning JSON-RPC error to client): \(errorDescription)")
                let errorResponse = MCP.Core.Protocols.JSONRPCError(
                    id: request.id,
                    error: MCP.Core.Protocols.JSONRPCError.ErrorDetail(
                        code: detailCode,
                        message: detailMessage
                    )
                )
                try await transport.send(.error(errorResponse))
            }
        }

        private func handleNotification(_ notification: MCP.Core.Protocols.JSONRPCNotification) async throws {
            // Handle notifications (currently none defined for server)
            logInfo("Received notification: \(notification.method)")
        }

        // MARK: - MCP.Core.Protocols.Request Routing

        private func routeRequest(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            switch request.method {
            // Initialization
            case MCP.Core.Protocols.Method.initialize:
                return try await handleInitialize(request)

            // Resources
            case MCP.Core.Protocols.Method.resourcesList:
                try ensureInitialized()
                return try await handleListResources(request)

            case MCP.Core.Protocols.Method.resourcesRead:
                try ensureInitialized()
                return try await handleReadResource(request)

            case MCP.Core.Protocols.Method.resourcesTemplatesList:
                try ensureInitialized()
                return try await handleListResourceTemplates(request)

            // Tools
            case MCP.Core.Protocols.Method.toolsList:
                try ensureInitialized()
                return try await handleListTools(request)

            case MCP.Core.Protocols.Method.toolsCall:
                try ensureInitialized()
                return try await handleCallTool(request)

            // Prompts
            case MCP.Core.Protocols.Method.promptsList:
                try ensureInitialized()
                return try await handleListPrompts(request)

            case MCP.Core.Protocols.Method.promptsGet:
                try ensureInitialized()
                return try await handleGetPrompt(request)

            default:
                throw ServerError.methodNotFound(request.method)
            }
        }

        // MARK: - Handler Methods

        private func handleInitialize(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            guard !isInitialized else {
                throw ServerError.alreadyInitialized
            }

            // Parse initialize params and negotiate protocol version
            let params = try decodeParams(MCP.Core.Protocols.InitializeRequest.Params.self, from: request.params)
            let negotiatedVersion = try negotiateProtocolVersion(clientVersion: params.protocolVersion)

            let result = MCP.Core.Protocols.InitializeResult(
                protocolVersion: negotiatedVersion,
                capabilities: capabilities,
                serverInfo: serverInfo
            )

            isInitialized = true
            logInfo("Server initialized (protocol \(negotiatedVersion))")

            return try encodeResult(result)
        }

        private func handleListResources(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            guard let provider = resourceProvider else {
                throw ServerError.capabilityNotSupported("resources")
            }

            let cursor = request.params?["cursor"]?.value as? String
            let result = try await provider.listResources(cursor: cursor)
            return try encodeResult(result)
        }

        private func handleReadResource(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            guard let provider = resourceProvider else {
                throw ServerError.capabilityNotSupported("resources")
            }

            guard let uri = request.params?["uri"]?.value as? String else {
                throw ServerError.invalidParams("Missing required parameter: uri")
            }

            let result = try await provider.readResource(uri: uri)
            return try encodeResult(result)
        }

        private func handleListResourceTemplates(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            guard let provider = resourceProvider else {
                throw ServerError.capabilityNotSupported("resources")
            }

            let cursor = request.params?["cursor"]?.value as? String
            let result = try await provider.listResourceTemplates(cursor: cursor)
            return try encodeResult(result ?? MCP.Core.Protocols.ListResourceTemplatesResult(resourceTemplates: []))
        }

        private func handleListTools(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            guard let provider = toolProvider else {
                throw ServerError.capabilityNotSupported("tools")
            }

            let cursor = request.params?["cursor"]?.value as? String
            let result = try await provider.listTools(cursor: cursor)
            return try encodeResult(result)
        }

        private func handleCallTool(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            guard let provider = toolProvider else {
                throw ServerError.capabilityNotSupported("tools")
            }

            guard let name = request.params?["name"]?.value as? String else {
                throw ServerError.invalidParams("Missing required parameter: name")
            }

            // Extract arguments dictionary preserving MCP.Core.Protocols.AnyCodable wrappers
            let arguments = request.params?["arguments"]?.dictionaryValue

            let result = try await provider.callTool(name: name, arguments: arguments)
            return try encodeResult(result)
        }

        private func handleListPrompts(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            guard let provider = promptProvider else {
                throw ServerError.capabilityNotSupported("prompts")
            }

            let cursor = request.params?["cursor"]?.value as? String
            let result = try await provider.listPrompts(cursor: cursor)
            return try encodeResult(result)
        }

        private func handleGetPrompt(_ request: MCP.Core.Protocols.JSONRPCRequest) async throws -> [String: MCP.Core.Protocols.AnyCodable] {
            guard let provider = promptProvider else {
                throw ServerError.capabilityNotSupported("prompts")
            }

            guard let name = request.params?["name"]?.value as? String else {
                throw ServerError.invalidParams("Missing required parameter: name")
            }

            let arguments = request.params?["arguments"]?.value as? [String: String]
            let result = try await provider.getPrompt(name: name, arguments: arguments)
            return try encodeResult(result)
        }

        // MARK: - Helper Methods

        private func ensureInitialized() throws {
            guard isInitialized else {
                throw ServerError.notInitialized
            }
        }

        private func encodeResult(_ value: some Encodable) throws -> [String: MCP.Core.Protocols.AnyCodable] {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            let decoder = JSONDecoder()
            return try decoder.decode([String: MCP.Core.Protocols.AnyCodable].self, from: data)
        }

        private func decodeParams<T: Decodable>(
            _ type: T.Type,
            from params: [String: MCP.Core.Protocols.AnyCodable]?
        ) throws -> T {
            guard let params else {
                throw ServerError.invalidParams("Missing params")
            }

            let encoder = JSONEncoder()
            let data = try encoder.encode(params)

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ServerError.invalidParams("Invalid params: \(error.localizedDescription)")
            }
        }

        private func negotiateProtocolVersion(clientVersion: String) throws -> String {
            if MCPProtocolVersionsSupported.contains(clientVersion) {
                return clientVersion
            }

            // Version strings are in YYYY-MM-DD format, so lexicographic order works.
            let compatibleVersions = MCPProtocolVersionsSupported.filter { $0 <= clientVersion }
            if let best = compatibleVersions.sorted().last {
                return best
            }

            let supported = MCPProtocolVersionsSupported.joined(separator: ", ")
            throw ServerError.invalidParams(
                "Unsupported protocol version \(clientVersion). Supported: \(supported)"
            )
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            fputs("ℹ️  \(message)\n", stderr)
        }

        private func logWarning(_ message: String) {
            fputs("⚠️  \(message)\n", stderr)
        }

        private func logError(_ message: String) {
            fputs("❌ \(message)\n", stderr)
        }
    }
}

// MARK: - Server Errors

extension MCP.Core {
    public enum ServerError: Error, LocalizedError {
        case alreadyRunning
        case transportNotConnected
        case notInitialized
        case alreadyInitialized
        case methodNotFound(String)
        case invalidParams(String)
        case capabilityNotSupported(String)
        case encodingFailed

        public var code: Int {
            switch self {
            case .notInitialized, .alreadyInitialized:
                return MCP.Core.Protocols.ErrorCode.invalidRequest.rawValue
            case .methodNotFound:
                return MCP.Core.Protocols.ErrorCode.methodNotFound.rawValue
            case .invalidParams:
                return MCP.Core.Protocols.ErrorCode.invalidParams.rawValue
            default:
                return MCP.Core.Protocols.ErrorCode.internalError.rawValue
            }
        }

        public var message: String {
            switch self {
            case .alreadyRunning:
                return "Server is already running"
            case .transportNotConnected:
                return "Transport is not connected"
            case .notInitialized:
                return "Server has not been initialized. Call initialize first."
            case .alreadyInitialized:
                return "Server has already been initialized"
            case .methodNotFound(let method):
                return "MCP.Core.Protocols.Method not found: \(method)"
            case .invalidParams(let details):
                return "Invalid parameters: \(details)"
            case .capabilityNotSupported(let capability):
                return "Capability not supported: \(capability)"
            case .encodingFailed:
                return "Failed to encode response"
            }
        }

        public var errorDescription: String? {
            message
        }
    }
}
