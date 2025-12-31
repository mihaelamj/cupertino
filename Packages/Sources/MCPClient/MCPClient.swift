import Foundation
import MCP

// MARK: - MCP Client

/// A reusable MCP client that connects to an MCP server via stdio.
/// Can be used by CLI tools, SwiftUI apps, or any other Swift application.
public actor MCPClient {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var messageID = 0
    private var responseBuffer = ""
    private var pendingResponses: [CheckedContinuation<String, Error>] = []

    private let serverCommand: [String]
    private let serverArguments: [String]

    /// Server information after initialization
    public private(set) var serverInfo: Implementation?
    public private(set) var serverCapabilities: ServerCapabilities?
    public private(set) var protocolVersion: String?

    /// Whether the client is connected to a server
    public var isConnected: Bool {
        process?.isRunning ?? false
    }

    // MARK: - Initialization

    /// Create an MCP client that will connect to a server via stdio
    /// - Parameters:
    ///   - serverCommand: The executable to run (e.g., "cupertino" or "npx")
    ///   - serverArguments: Arguments to pass (e.g., ["serve"] or ["-y", "@modelcontextprotocol/server-memory"])
    public init(serverCommand: String, serverArguments: [String] = []) {
        self.serverCommand = [serverCommand]
        self.serverArguments = serverArguments
    }

    /// Create an MCP client with a full command array
    /// - Parameter command: Full command array (e.g., ["npx", "-y", "@modelcontextprotocol/server-memory"])
    public init(command: [String]) {
        guard !command.isEmpty else {
            serverCommand = []
            serverArguments = []
            return
        }
        serverCommand = [command[0]]
        serverArguments = Array(command.dropFirst())
    }

    // MARK: - Connection Management

    /// Start the MCP server and establish connection
    public func connect() async throws {
        guard !serverCommand.isEmpty else {
            throw MCPClientError.invalidCommand
        }

        process = Process()

        // Set up the executable
        let executable = serverCommand[0]
        if executable.hasPrefix("/") {
            process?.executableURL = URL(fileURLWithPath: executable)
            process?.arguments = serverArguments
        } else {
            // Use env to find the executable in PATH
            process?.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process?.arguments = [executable] + serverArguments
        }

        // Set up pipes for stdio
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process?.standardInput = stdinPipe
        process?.standardOutput = stdoutPipe
        process?.standardError = stderrPipe

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        // Set up readability handler for stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                Task {
                    await self?.handleIncomingData(text)
                }
            }
        }

        try process?.run()

        // Give server time to start
        try await Task.sleep(for: .seconds(0.5))

        // Initialize the MCP connection
        try await initialize()
    }

    /// Disconnect from the server
    public func disconnect() {
        stdin?.closeFile()
        stdout?.closeFile()
        process?.terminate()
        process?.waitUntilExit()

        process = nil
        stdin = nil
        stdout = nil
        serverInfo = nil
        serverCapabilities = nil
        protocolVersion = nil
    }

    // MARK: - MCP Protocol Methods

    /// Initialize the MCP connection
    private func initialize() async throws {
        let versions = preferredProtocolVersions()
        var lastError: Error?

        for version in versions {
            let request = MCPRequest(
                jsonrpc: "2.0",
                id: .int(nextMessageID()),
                method: "initialize",
                params: InitializeParams(
                    protocolVersion: version,
                    capabilities: ClientCapabilities(
                        experimental: nil,
                        sampling: nil,
                        roots: RootsCapability(listChanged: true)
                    ),
                    clientInfo: Implementation(name: "MCPClient", version: "1.0.0")
                )
            )

            do {
                let response: InitializeResult = try await sendRequest(request)
                serverInfo = response.serverInfo
                serverCapabilities = response.capabilities
                protocolVersion = response.protocolVersion
                return
            } catch let error as MCPClientError {
                lastError = error
                if shouldRetryInitialize(error: error) {
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }

        throw lastError ?? MCPClientError.serverError("Unsupported protocol version")
    }

    private func preferredProtocolVersions() -> [String] {
        var ordered = [MCPProtocolVersion]
        for version in MCPProtocolVersionsSupported where !ordered.contains(version) {
            ordered.append(version)
        }
        return ordered
    }

    private func shouldRetryInitialize(error: MCPClientError) -> Bool {
        guard case let .serverError(message) = error else {
            return false
        }

        let lower = message.lowercased()
        return lower.contains("protocol") || lower.contains("version")
    }

    /// List available tools from the server
    public func listTools() async throws -> [Tool] {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "tools/list",
            params: EmptyParams()
        )

        let response: ListToolsResult = try await sendRequest(request)
        return response.tools
    }

    /// Call a tool on the server
    /// - Parameters:
    ///   - name: Tool name
    ///   - arguments: Tool arguments as a dictionary
    /// - Returns: Tool call result with content blocks
    public func callTool(name: String, arguments: [String: AnyCodable]? = nil) async throws -> CallToolResult {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "tools/call",
            params: CallToolParams(name: name, arguments: arguments)
        )

        return try await sendRequest(request)
    }

    /// List available resources from the server
    public func listResources() async throws -> [Resource] {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "resources/list",
            params: EmptyParams()
        )

        let response: ListResourcesResult = try await sendRequest(request)
        return response.resources
    }

    /// Read a resource from the server
    /// - Parameter uri: Resource URI
    /// - Returns: Resource contents
    public func readResource(uri: String) async throws -> ReadResourceResult {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "resources/read",
            params: ReadResourceParams(uri: uri)
        )

        return try await sendRequest(request)
    }

    // MARK: - Low-level Communication

    private func sendRequest<R: Decodable>(_ request: MCPRequest<some Codable & Sendable>) async throws -> R {
        guard let stdin, let stdout else {
            throw MCPClientError.notConnected
        }

        // Encode compact JSON for the wire
        let wireEncoder = JSONEncoder()
        wireEncoder.outputFormatting = [.sortedKeys]
        let wireData = try wireEncoder.encode(request)

        guard var wireString = String(data: wireData, encoding: .utf8) else {
            throw MCPClientError.encodingFailed
        }

        // MCP stdio: messages are newline-delimited
        if wireString.contains("\n") {
            wireString = wireString.replacingOccurrences(of: "\n", with: "")
        }

        let message = wireString + "\n"
        let messageData = Data(message.utf8)

        // Write the message
        stdin.write(messageData)

        // Wait for response
        let responseLine = try await readLine(from: stdout)

        // Decode response
        let responseData = Data(responseLine.utf8)

        // Check for error response
        if let errorResponse = try? JSONDecoder().decode(JSONRPCError.self, from: responseData) {
            throw MCPClientError.serverError(errorResponse.error.message)
        }

        // Decode success response
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)

        // Convert result to specific type
        let resultData = try JSONEncoder().encode(response.result)
        return try JSONDecoder().decode(R.self, from: resultData)
    }

    private func handleIncomingData(_ text: String) {
        responseBuffer += text

        while let newlineRange = responseBuffer.range(of: "\n") {
            let line = String(responseBuffer[..<newlineRange.lowerBound])
            responseBuffer.removeSubrange(...newlineRange.lowerBound)

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }

            if !pendingResponses.isEmpty {
                let continuation = pendingResponses.removeFirst()
                continuation.resume(returning: line)
            }
        }
    }

    private func readLine(from fileHandle: FileHandle) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            pendingResponses.append(continuation)
        }
    }

    private func nextMessageID() -> Int {
        messageID += 1
        return messageID
    }
}

// MARK: - Helper Types

struct EmptyParams: Codable, Sendable {}

// MARK: - Errors

public enum MCPClientError: Error, LocalizedError {
    case invalidCommand
    case notConnected
    case encodingFailed
    case decodingFailed
    case noResponse
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "Invalid server command"
        case .notConnected:
            return "Not connected to MCP server"
        case .encodingFailed:
            return "Failed to encode request"
        case .decodingFailed:
            return "Failed to decode response"
        case .noResponse:
            return "No response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
