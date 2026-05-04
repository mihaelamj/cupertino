import Foundation
import MCP
import Shared

// MARK: - Mock AI Agent

// swiftlint:disable type_body_length
// Justification: MCPClient actor implements a complete MCP client for testing.
// It handles: process management, JSON-RPC communication, request/response formatting, and demo flows.
// The actor maintains state across multiple async operations for the test session.

// A mock AI agent that demonstrates how to send MCP requests to an MCP server
// This helps visualize the complete MCP request/response cycle with full JSON logging

@main
struct MockAIAgent {
    static func main() async throws {
        // Force flush output immediately
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        // Handle --version flag
        let rawArgs = CommandLine.arguments
        if rawArgs.contains("--version") || rawArgs.contains("-v") {
            print(Shared.Constants.App.version)
            return
        }

        // Parse --quiet (presentation/demo mode): suppress raw JSON dumps,
        // server stderr echoes, and the base64 icon blob. Pretty-printed
        // SERVER → CLIENT response sections are kept so the demo still
        // tells a story without burying the audience in protocol noise.
        let quiet = rawArgs.contains("--quiet") || rawArgs.contains("-q")
        let args = rawArgs.filter { $0 != "--quiet" && $0 != "-q" }

        print("🤖 Mock AI Agent Starting...")
        print("=".repeating(80))
        print()

        // Parse command line arguments
        var serverCommand: [String]?

        if args.count > 1 {
            // External server mode: mock-ai-agent npx -y @modelcontextprotocol/server-memory
            serverCommand = Array(args.dropFirst())
            print("📡 Using external MCP server:")
            print("   Command: \(serverCommand!.joined(separator: " "))")
            print()
        }

        do {
            let agent = MCPClient(externalServerCommand: serverCommand, quiet: quiet)
            try await agent.run()
        } catch {
            print("❌ Error: \(error)")
            throw error
        }
    }
}

// MARK: - MCP Client

actor MCPClient {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var messageID = 0
    private let externalServerCommand: [String]?
    private let quiet: Bool
    private var pendingResponses: [CheckedContinuation<String, Error>] = []

    init(externalServerCommand: [String]? = nil, quiet: Bool = false) {
        self.externalServerCommand = externalServerCommand
        self.quiet = quiet
    }

    func run() async throws {
        // Start the MCP server
        try startMCPServer()

        // Give server time to start
        try await Task.sleep(for: .seconds(1))

        print("📡 Starting MCP Communication...")
        print("=".repeating(80))
        print()

        // Initialize the connection
        try await initialize()

        // List available tools
        try await listTools()

        // Call unified search tool
        try await callSearchTool(query: "SwiftUI")

        // List available resources
        try await listResources()

        // Read one of the search results
        // Use a known URI from the indexed documentation
        let testURI = Shared.Constants.Search.appleDocsScheme + "swiftui/documentation_swiftui_view"
        try await readResource(uri: testURI)

        // Shutdown
        try await shutdown()

        print()
        print("=".repeating(80))
        print("✅ Mock AI Agent Complete")

        // Keep process alive briefly to see final output
        try await Task.sleep(for: .seconds(1))

        // Cleanup
        cleanup()
    }

    // MARK: - Server Management

    private func startMCPServer() throws {
        print("🚀 Starting MCP Server Process...")
        print()

        process = Process()

        if let externalCommand = externalServerCommand {
            // Use external server command
            let executable = externalCommand[0]
            let arguments = Array(externalCommand.dropFirst())

            process?.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process?.arguments = [executable] + arguments

            print("   Using external server: \(executable) \(arguments.joined(separator: " "))")
        } else {
            // Get the path to cupertino executable
            let serverPath = findCupertinoExecutable()
            process?.executableURL = URL(fileURLWithPath: serverPath)
            process?.arguments = ["serve"]
            print("   Using cupertino server: \(serverPath)")
        }
        print()

        // Set up pipes for stdio
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process?.standardInput = stdinPipe
        process?.standardOutput = stdoutPipe
        process?.standardError = stderrPipe

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        // Stream stdout as ordered, complete lines via bytes.lines. The
        // previous readabilityHandler approach spawned a fresh Task per
        // chunk, so chunks could be processed on the actor out of order
        // when the response straddled the pipe buffer (~32 KB). bytes.lines
        // delivers lines in arrival order with internal buffering that
        // handles UTF-8 boundaries correctly.
        Task { [weak self] in
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    await self?.handleLine(line)
                }
            } catch {
                // pipe closed or read failed — server has exited.
            }
        }

        // Log stderr from server (suppressed in --quiet demo mode)
        let echoStderr = !quiet
        Task {
            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                if echoStderr {
                    print("  [SERVER STDERR] \(line)")
                }
            }
        }

        try process?.run()

        print("✅ MCP Server Started (PID: \(process?.processIdentifier ?? 0))")
        print()
    }

    private func findCupertinoExecutable() -> String {
        // ONLY use local build - never fall back to installed version
        // This ensures we're testing the current code, not an installed version
        let buildLocations = [
            ".build/debug/cupertino",
            ".build/release/cupertino",
        ]

        for location in buildLocations where FileManager.default.fileExists(atPath: location) {
            return location
        }

        // Fail with clear error if not built
        print("❌ ERROR: No local build found!")
        print("   MockAIAgent requires a local build to test current code.")
        print("   Run: swift build")
        print("   Then: swift run mock-ai-agent")
        print()
        print("   (Not using /usr/local/bin/cupertino to avoid testing installed version)")
        fatalError("Build cupertino first: swift build")
    }

    private func cleanup() {
        print()
        print("🧹 Cleaning up...")
        stdin?.closeFile()
        stdout?.closeFile()
        process?.terminate()
        process?.waitUntilExit()
        print("✅ Cleanup complete")
    }

    // MARK: - MCP Protocol Methods

    private func initialize() async throws {
        print("📨 CLIENT → SERVER: initialize")
        print("-".repeating(80))

        // Try each supported version, starting with newest
        var lastError: Error?
        for version in MCPProtocolVersionsSupported {
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
                    clientInfo: Implementation(name: "Mock AI Agent", version: "1.0.0")
                )
            )

            do {
                let response: InitializeResult = try await sendRequest(request) as InitializeResult

                print()
                print("📬 SERVER → CLIENT: initialize response")
                print("-".repeating(80))
                logJSON(response)
                print()

                print("✅ Initialized with server: \(response.serverInfo.name) v\(response.serverInfo.version)")
                print("   Protocol Version: \(response.protocolVersion)")
                print("   Capabilities:")
                if let tools = response.capabilities.tools {
                    print("     - Tools: \(tools.listChanged ?? false ? "✓" : "✗")")
                }
                if let resources = response.capabilities.resources {
                    let listChanged = resources.listChanged ?? false ? "✓" : "✗"
                    let subscribe = resources.subscribe ?? false ? "✓" : "✗"
                    print("     - Resources: \(listChanged) (subscribe: \(subscribe))")
                }
                print()
                return
            } catch let error as MCPClientError {
                lastError = error
                // Retry with older version if protocol/version error
                if case let .serverError(message) = error,
                   message.lowercased().contains("protocol") || message.lowercased().contains("version") {
                    print("⚠️  Version \(version) not supported, trying fallback...")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? MCPClientError.serverError("No supported protocol version")
    }

    private func listTools() async throws {
        print("📨 CLIENT → SERVER: tools/list")
        print("-".repeating(80))

        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "tools/list",
            params: EmptyParams()
        )

        let response: ListToolsResult = try await sendRequest(request)

        print()
        print("📬 SERVER → CLIENT: tools/list response")
        print("-".repeating(80))
        logJSON(response)
        print()

        print("✅ Found \(response.tools.count) tools:")
        for tool in response.tools {
            print("   - \(tool.name): \(tool.description ?? "(no description)")")
            let schema = tool.inputSchema
            print("     Input schema: \(schema.type)")
            if let properties = schema.properties {
                print("     Properties: \(properties.keys.joined(separator: ", "))")
            }
        }
        print()
    }

    private func callSearchNodesTool(query: String) async throws {
        print("📨 CLIENT → SERVER: tools/call (search_nodes)")
        print("-".repeating(80))
        print("   Query: \"\(query)\"")
        print()

        let arguments: [String: AnyCodable] = [
            "query": AnyCodable(query),
        ]

        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "tools/call",
            params: CallToolParams(name: "search_nodes", arguments: arguments)
        )

        logRequestJSON(request)

        let response: CallToolResult = try await sendRequest(request)

        print()
        print("📬 SERVER → CLIENT: tools/call response")
        print("-".repeating(80))
        logJSON(response)
        print()

        print("✅ Tool execution complete")
        if response.isError ?? false {
            print("   ⚠️  Tool reported an error")
        }
        print("   Content items: \(response.content.count)")
        for (index, content) in response.content.enumerated() {
            switch content {
            case .text(let textContent):
                print("   [\(index + 1)] Type: text")
                let preview = String(textContent.text.prefix(100))
                print("       Preview: \(preview)\(textContent.text.count > 100 ? "..." : "")")
            case .image(let imageContent):
                print("   [\(index + 1)] Type: image")
                print("       MIME: \(imageContent.mimeType)")
            case .resource(let resourceContent):
                print("   [\(index + 1)] Type: resource")
                print("       Resource: \(resourceContent.resource)")
            }
        }
        print()
    }

    private func callSearchTool(query: String) async throws {
        typealias MCP = Shared.Constants.Search
        print("📨 CLIENT → SERVER: tools/call (\(MCP.toolSearch))")
        print("-".repeating(80))
        print("   Query: \"\(query)\"")
        print()

        let arguments: [String: AnyCodable] = [
            "query": AnyCodable(query),
            "limit": AnyCodable(5),
        ]

        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "tools/call",
            params: CallToolParams(name: MCP.toolSearch, arguments: arguments)
        )

        logRequestJSON(request)

        let response: CallToolResult = try await sendRequest(request)

        print()
        print("📬 SERVER → CLIENT: tools/call response")
        print("-".repeating(80))
        logJSON(response)
        print()

        print("✅ Tool execution complete")
        if response.isError ?? false {
            print("   ⚠️  Tool reported an error")
        }
        print("   Content items: \(response.content.count)")
        for (index, content) in response.content.enumerated() {
            switch content {
            case .text(let textContent):
                print("   [\(index + 1)] Type: text")
                let preview = String(textContent.text.prefix(100))
                print("       Preview: \(preview)\(textContent.text.count > 100 ? "..." : "")")
            case .image(let imageContent):
                print("   [\(index + 1)] Type: image")
                print("       MIME: \(imageContent.mimeType)")
            case .resource(let resourceContent):
                print("   [\(index + 1)] Type: resource")
                print("       Resource: \(resourceContent.resource)")
            }
        }
        print()
    }

    private func listResources() async throws {
        print("📨 CLIENT → SERVER: resources/list")
        print("-".repeating(80))

        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "resources/list",
            params: EmptyParams()
        )

        let response: ListResourcesResult = try await sendRequest(request)

        print()
        print("📬 SERVER → CLIENT: resources/list response")
        print("-".repeating(80))
        logJSON(response)
        print()

        print("✅ Found \(response.resources.count) resources:")
        for resource in response.resources {
            print("   - \(resource.uri): \(resource.name)")
            if let description = resource.description {
                print("     \(description)")
            }
            if let mimeType = resource.mimeType {
                print("     MIME: \(mimeType)")
            }
        }
        print()
    }

    private func readResource(uri: String) async throws {
        print("📨 CLIENT → SERVER: resources/read")
        print("-".repeating(80))
        print("   URI: \(uri)")
        print()

        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(nextMessageID()),
            method: "resources/read",
            params: ReadResourceParams(uri: uri)
        )

        logRequestJSON(request)

        let response: ReadResourceResult = try await sendRequest(request)

        print()
        print("📬 SERVER → CLIENT: resources/read response")
        print("-".repeating(80))
        logJSON(response)
        print()

        print("✅ Resource read complete")
        print("   Content items: \(response.contents.count)")
        for (index, content) in response.contents.enumerated() {
            switch content {
            case .text(let textContents):
                print("   [\(index + 1)] Text Resource")
                print("       URI: \(textContents.uri)")
                print("       MIME: \(textContents.mimeType ?? "unknown")")
                let preview = String(textContents.text.prefix(100))
                print("       Preview: \(preview)\(textContents.text.count > 100 ? "..." : "")")
            case .blob(let blobContents):
                print("   [\(index + 1)] Blob Resource")
                print("       URI: \(blobContents.uri)")
                print("       MIME: \(blobContents.mimeType ?? "unknown")")
                print("       Size: \(blobContents.blob.count) bytes (base64)")
            }
        }
        print()
    }

    private func shutdown() async throws {
        print("📨 CLIENT → SERVER: shutdown (notification)")
        print("-".repeating(80))

        let notification = JSONRPCNotification(
            method: "notifications/cancelled",
            params: nil
        )

        try sendNotification(notification)
        print("✅ Shutdown notification sent")
        print()
    }

    // MARK: - Low-level Communication

    private func sendRequest<R: Decodable>(_ request: MCPRequest<some Codable & Sendable>) async throws -> R {
        guard let stdin, let stdout else {
            throw MCPClientError.notConnected
        }

        // 1) Encode *compact* JSON for the wire (no prettyPrinted!)
        let wireEncoder = JSONEncoder()
        wireEncoder.outputFormatting = [.sortedKeys] // deterministic order, but NOT .prettyPrinted
        let wireData = try wireEncoder.encode(request)

        guard var wireString = String(data: wireData, encoding: .utf8) else {
            throw MCPClientError.encodingFailed
        }

        // MCP stdio: messages are newline-delimited, MUST NOT contain embedded newlines
        if wireString.contains("\n") {
            wireString = wireString.replacingOccurrences(of: "\n", with: "")
        }

        let message = wireString + "\n"
        let messageData = Data(message.utf8)

        // 2) Log a *pretty* version separately, so logs stay nice.
        //    In --quiet demo mode we skip the request dump; the dedicated
        //    "📨 CLIENT → SERVER: <method>" line above already names the call.
        if !quiet {
            print()
            print("📤 Sending JSON:")
            logJSON(request)
            print()
        }

        // 3) Write the complete message
        stdin.write(messageData)

        // 4) Wait for one newline-delimited response
        let responseLine = try await readLine(from: stdout)

        // Log the raw JSON response (skipped in demo mode — the dedicated
        // pretty "📬 SERVER → CLIENT: <method> response" block follows).
        if !quiet {
            print()
            print("📥 Received JSON:")
            print(responseLine)
            print()
        }

        // Decode response
        guard let responseData = responseLine.data(using: String.Encoding.utf8) else {
            throw MCPClientError.decodingFailed
        }

        // Try to decode as error first
        if let errorResponse = try? JSONDecoder().decode(JSONRPCError.self, from: responseData) {
            throw MCPClientError.serverError(errorResponse.error.message)
        }

        // Decode as success response
        let decoder = JSONDecoder()
        let response = try decoder.decode(JSONRPCResponse.self, from: responseData)

        // Convert result dictionary to our specific type
        let resultData = try JSONEncoder().encode(response.result)
        return try JSONDecoder().decode(R.self, from: resultData)
    }

    private func sendNotification(_ notification: JSONRPCNotification) throws {
        guard let stdin else {
            throw MCPClientError.notConnected
        }

        // 1) Encode compact JSON for the wire (no prettyPrinted!)
        let wireEncoder = JSONEncoder()
        wireEncoder.outputFormatting = [.sortedKeys] // no .prettyPrinted
        let wireData = try wireEncoder.encode(notification)

        guard var wireString = String(data: wireData, encoding: .utf8) else {
            throw MCPClientError.encodingFailed
        }

        // MCP stdio: messages are newline-delimited, MUST NOT contain embedded newlines
        if wireString.contains("\n") {
            wireString = wireString.replacingOccurrences(of: "\n", with: "")
        }

        let message = wireString + "\n"
        let messageData = Data(message.utf8)

        // 2) Log pretty version for display (skipped in --quiet demo mode)
        if !quiet {
            print()
            print("📤 Sending Notification JSON:")
            logJSON(notification)
            print()
        }

        // 3) Write the wire message
        stdin.write(messageData)
    }

    private func handleLine(_ line: String) {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return
        }

        if !pendingResponses.isEmpty {
            let continuation = pendingResponses.removeFirst()
            continuation.resume(returning: line)
        } else {
            print("⚠️  Received unexpected line: \(line.prefix(100))...")
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

    // MARK: - Logging Helpers

    private func logJSON(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let jsonData = try? encoder.encode(value),
           let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) {
            print(quiet ? Self.truncateBase64Blobs(jsonString) : jsonString)
        }
    }

    /// Replace any string longer than 200 chars that looks like a `data:` base64
    /// blob (or just a long base64 run) with a short placeholder, so the icon
    /// PNG embedded in `serverInfo.icons[].src` doesn't dump a multi-line
    /// base64 wall into the demo output.
    private static func truncateBase64Blobs(_ json: String) -> String {
        let pattern = #""(data:[^"]{60,}|[A-Za-z0-9+/=]{200,})""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return json }
        let range = NSRange(json.startIndex..., in: json)
        return regex.stringByReplacingMatches(
            in: json,
            range: range,
            withTemplate: #""<…base64 truncated for demo…>""#
        )
    }

    private func logRequestJSON(_ request: MCPRequest<some Codable & Sendable>) {
        print()
        print("📤 Request JSON:")
        logJSON(request)
    }
}

// MARK: - Helper Types

struct EmptyParams: Codable, Sendable {}

// MARK: - Errors

enum MCPClientError: Error, CustomStringConvertible {
    case notConnected
    case encodingFailed
    case decodingFailed
    case noResponse
    case noResult
    case serverError(String)

    var description: String {
        switch self {
        case .notConnected:
            return "Not connected to MCP server"
        case .encodingFailed:
            return "Failed to encode request"
        case .decodingFailed:
            return "Failed to decode response"
        case .noResponse:
            return "No response from server"
        case .noResult:
            return "Response contains no result"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - Extensions

extension String {
    func repeating(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
