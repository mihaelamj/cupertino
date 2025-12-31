import Foundation
@testable import MCP
import Testing

// MARK: - MCP Framework Tests

/// Tests for the core MCP (Model Context Protocol) framework
/// This is the base cross-platform framework for MCP communication

// MARK: - JSON-RPC 2.0 Protocol Tests

@Suite("JSON-RPC 2.0 Protocol")
struct JSONRPCProtocolTests {
    // MARK: - RequestID Tests

    @Test("RequestID encodes and decodes string variant")
    func requestIDString() throws {
        let requestID = RequestID.string("test-123")

        let encoder = JSONEncoder()
        let data = try encoder.encode(requestID)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RequestID.self, from: data)

        #expect(decoded == requestID)

        if case .string(let value) = decoded {
            #expect(value == "test-123")
        } else {
            Issue.record("Expected string variant")
        }
    }

    @Test("RequestID encodes and decodes int variant")
    func requestIDInt() throws {
        let requestID = RequestID.int(42)

        let encoder = JSONEncoder()
        let data = try encoder.encode(requestID)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RequestID.self, from: data)

        #expect(decoded == requestID)

        if case .int(let value) = decoded {
            #expect(value == 42)
        } else {
            Issue.record("Expected int variant")
        }
    }

    @Test("RequestID is Hashable")
    func requestIDHashable() {
        let id1 = RequestID.string("test")
        let id2 = RequestID.string("test")
        let id3 = RequestID.int(1)

        #expect(id1 == id2)
        #expect(id1 != id3)

        let set: Set<RequestID> = [id1, id2, id3]
        #expect(set.count == 2) // id1 and id2 are identical
    }

    // MARK: - JSONRPCRequest Tests

    @Test("JSONRPCRequest serializes correctly")
    func jsonRPCRequestSerialization() throws {
        let request = JSONRPCRequest(
            id: .int(1),
            method: "initialize",
            params: ["test": AnyCodable("value")]
        )

        #expect(request.jsonrpc == "2.0")
        #expect(request.method == "initialize")
        #expect(request.params?["test"]?.value as? String == "value")

        // Verify it can be encoded
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        #expect(!data.isEmpty)

        // Verify it can be decoded
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCRequest.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.method == "initialize")
    }

    @Test("JSONRPCRequest handles nil params")
    func jsonRPCRequestNilParams() throws {
        let request = JSONRPCRequest(
            id: .string("test-id"),
            method: "ping"
        )

        #expect(request.params == nil)

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCRequest.self, from: data)

        #expect(decoded.params == nil)
    }

    @Test("AnyCodable preserves dictionary type")
    func anyCodableDictionaryPreservation() throws {
        // Create a nested dictionary structure like tools/call request
        let innerDict: [String: AnyCodable] = [
            "query": AnyCodable("SwiftUI"),
            "limit": AnyCodable(5),
        ]

        let outerDict: [String: AnyCodable] = [
            "name": AnyCodable("search_docs"),
            "arguments": AnyCodable(innerDict),
        ]

        // Verify we can extract the nested dictionary
        guard let extractedArgs = outerDict["arguments"]?.dictionaryValue else {
            Issue.record("Failed to extract arguments dictionary")
            return
        }

        // Verify the nested values
        #expect(extractedArgs["query"]?.value as? String == "SwiftUI")
        #expect(extractedArgs["limit"]?.value as? Int == 5)
    }

    @Test("JSONRPCRequest tools/call argument extraction")
    func toolsCallArgumentExtraction() throws {
        // Simulate the exact structure from a tools/call request
        let arguments: [String: AnyCodable] = [
            "query": AnyCodable("SwiftUI"),
            "limit": AnyCodable(5),
        ]

        let params: [String: AnyCodable] = [
            "name": AnyCodable("search_docs"),
            "arguments": AnyCodable(arguments),
        ]

        let request = JSONRPCRequest(
            id: .int(3),
            method: "tools/call",
            params: params
        )

        // Encode and decode to simulate wire protocol
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCRequest.self, from: data)

        // Extract name
        guard let name = decoded.params?["name"]?.value as? String else {
            Issue.record("Failed to extract name")
            return
        }
        #expect(name == "search_docs")

        // Extract arguments using dictionaryValue
        guard let extractedArgs = decoded.params?["arguments"]?.dictionaryValue else {
            Issue.record("Failed to extract arguments dictionary")
            return
        }

        // Verify nested arguments
        guard let query = extractedArgs["query"]?.value as? String else {
            Issue.record("Failed to extract query from arguments")
            return
        }
        #expect(query == "SwiftUI")

        guard let limit = extractedArgs["limit"]?.value as? Int else {
            Issue.record("Failed to extract limit from arguments")
            return
        }
        #expect(limit == 5)
    }

    @Test("AnyCodable round-trip with nested dictionaries")
    func anyCodableRoundTrip() throws {
        // Create the exact JSON structure from the mock-ai-agent
        let jsonString = """
        {
          "id": 3,
          "jsonrpc": "2.0",
          "method": "tools/call",
          "params": {
            "arguments": {
              "limit": 5,
              "query": "SwiftUI"
            },
            "name": "search_docs"
          }
        }
        """

        let jsonData = Data(jsonString.utf8)

        // Decode the request
        let decoder = JSONDecoder()
        let request = try decoder.decode(JSONRPCRequest.self, from: jsonData)

        // Verify method
        #expect(request.method == "tools/call")

        // Extract name
        guard let name = request.params?["name"]?.value as? String else {
            Issue.record("Failed to extract name")
            return
        }
        #expect(name == "search_docs")

        // Extract arguments using dictionaryValue
        guard let args = request.params?["arguments"]?.dictionaryValue else {
            Issue.record("Failed to extract arguments dictionary using dictionaryValue")
            return
        }

        // Verify query
        guard let query = args["query"]?.value as? String else {
            let queryValueType = type(of: args["query"]?.value)
            Issue.record("Failed to extract query: args keys = \(args.keys), query value type = \(queryValueType)")
            return
        }
        #expect(query == "SwiftUI")

        // Verify limit
        guard let limit = args["limit"]?.value as? Int else {
            Issue.record("Failed to extract limit")
            return
        }
        #expect(limit == 5)
    }

    // MARK: - JSONRPCNotification Tests

    @Test("JSONRPCNotification serializes correctly")
    func jsonRPCNotificationSerialization() throws {
        let notification = JSONRPCNotification(
            method: "cancelled",
            params: ["requestId": AnyCodable("123")]
        )

        #expect(notification.jsonrpc == "2.0")
        #expect(notification.method == "cancelled")

        let encoder = JSONEncoder()
        let data = try encoder.encode(notification)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCNotification.self, from: data)

        #expect(decoded.method == "cancelled")
    }

    // MARK: - JSONRPCResponse Tests

    @Test("JSONRPCResponse serializes correctly")
    func jsonRPCResponseSerialization() throws {
        let response = JSONRPCResponse(
            id: .int(1),
            result: ["status": AnyCodable("ok")]
        )

        #expect(response.jsonrpc == "2.0")
        #expect(response.result["status"]?.value as? String == "ok")

        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCResponse.self, from: data)

        #expect(decoded.result["status"]?.value as? String == "ok")
    }

    // MARK: - JSONRPCError Tests

    @Test("JSONRPCError serializes correctly")
    func jsonRPCErrorSerialization() throws {
        let errorDetail = JSONRPCError.ErrorDetail(
            code: -32600,
            message: "Invalid Request",
            data: AnyCodable("Additional info")
        )

        let error = JSONRPCError(
            id: .string("bad-request"),
            error: errorDetail
        )

        #expect(error.jsonrpc == "2.0")
        #expect(error.error.code == -32600)
        #expect(error.error.message == "Invalid Request")

        let encoder = JSONEncoder()
        let data = try encoder.encode(error)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCError.self, from: data)

        #expect(decoded.error.code == -32600)
        #expect(decoded.error.message == "Invalid Request")
    }

    @Test("JSONRPCError handles nil data")
    func jsonRPCErrorNilData() throws {
        let errorDetail = JSONRPCError.ErrorDetail(
            code: -32601,
            message: "Method not found"
        )

        let error = JSONRPCError(
            id: .int(999),
            error: errorDetail
        )

        #expect(error.error.data == nil)

        let encoder = JSONEncoder()
        let data = try encoder.encode(error)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCError.self, from: data)

        #expect(decoded.error.data == nil)
    }
}

// MARK: - Content Block Tests

@Suite("Content Blocks")
struct ContentBlockTests {
    @Test("TextContent includes type field in JSON")
    func textContentIncludesType() throws {
        let content = TextContent(text: "Hello, world!")

        let encoder = JSONEncoder()
        let data = try encoder.encode(content)

        // Decode as raw JSON to verify structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["type"] as? String == "text")
        #expect(json?["text"] as? String == "Hello, world!")
    }

    @Test("ImageContent includes type field in JSON")
    func imageContentIncludesType() throws {
        let content = ImageContent(data: "base64data", mimeType: "image/png")

        let encoder = JSONEncoder()
        let data = try encoder.encode(content)

        // Decode as raw JSON to verify structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["type"] as? String == "image")
        #expect(json?["data"] as? String == "base64data")
        #expect(json?["mimeType"] as? String == "image/png")
    }

    @Test("EmbeddedResource includes type field in JSON")
    func embeddedResourceIncludesType() throws {
        let textResource = TextResourceContents(
            uri: "test://resource",
            mimeType: "text/plain",
            text: "test content"
        )
        let content = EmbeddedResource(resource: .text(textResource))

        let encoder = JSONEncoder()
        let data = try encoder.encode(content)

        // Decode as raw JSON to verify structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["type"] as? String == "resource")
        #expect(json?["resource"] != nil)
    }

    @Test("ContentBlock.text encodes with type field")
    func contentBlockTextEncoding() throws {
        let textContent = TextContent(text: "Test message")
        let block = ContentBlock.text(textContent)

        let encoder = JSONEncoder()
        let data = try encoder.encode([block])

        // Decode as raw JSON to verify structure
        let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let json = jsonArray?.first

        #expect(json?["type"] as? String == "text")
        #expect(json?["text"] as? String == "Test message")
    }

    @Test("CallToolResult encodes content blocks correctly")
    func callToolResultEncoding() throws {
        let textContent = TextContent(text: "Search results")
        let result = CallToolResult(content: [.text(textContent)])

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        // Verify it can be decoded back
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CallToolResult.self, from: data)

        #expect(decoded.content.count == 1)
        if case .text(let content) = decoded.content[0] {
            #expect(content.text == "Search results")
            #expect(content.type == "text")
        } else {
            Issue.record("Expected text content block")
        }
    }

    @Test("CallToolResult round-trip preserves type fields")
    func callToolResultRoundTrip() throws {
        // Create the JSON structure that would come from the server
        let jsonString = """
        {
          "content": [
            {
              "type": "text",
              "text": "Found 5 results"
            }
          ]
        }
        """

        let jsonData = Data(jsonString.utf8)

        // Decode
        let decoder = JSONDecoder()
        let result = try decoder.decode(CallToolResult.self, from: jsonData)

        // Re-encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedData = try encoder.encode(result)

        // Verify the re-encoded JSON includes type
        let reEncodedJson = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        let contentArray = reEncodedJson?["content"] as? [[String: Any]]
        let firstItem = contentArray?.first

        #expect(firstItem?["type"] as? String == "text")
        #expect(firstItem?["text"] as? String == "Found 5 results")
    }
}

// MARK: - MCP Protocol Types Tests

@Suite("MCP Protocol Types")
struct MCPProtocolTypesTests {
    @Test("MCP protocol version is defined")
    func protocolVersionDefined() {
        #expect(MCPProtocolVersion == "2025-06-18")
    }

    @Test("Implementation type works correctly")
    func implementationType() throws {
        let impl = Implementation(name: "cupertino", version: "1.0.0")

        #expect(impl.name == "cupertino")
        #expect(impl.version == "1.0.0")

        // Verify Codable
        let encoder = JSONEncoder()
        let data = try encoder.encode(impl)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Implementation.self, from: data)

        #expect(decoded.name == "cupertino")
        #expect(decoded.version == "1.0.0")
    }

    @Test("ClientCapabilities serializes correctly")
    func clientCapabilities() throws {
        let capabilities = ClientCapabilities(
            sampling: ClientCapabilities.SamplingCapability(),
            roots: ClientCapabilities.RootsCapability(listChanged: true)
        )

        #expect(capabilities.sampling != nil)
        #expect(capabilities.roots?.listChanged == true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(capabilities)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClientCapabilities.self, from: data)

        #expect(decoded.roots?.listChanged == true)
    }

    @Test("ServerCapabilities serializes correctly")
    func serverCapabilities() throws {
        let capabilities = ServerCapabilities(
            resources: ServerCapabilities.ResourcesCapability(
                subscribe: true,
                listChanged: true
            ),
            tools: ServerCapabilities.ToolsCapability(listChanged: false)
        )

        #expect(capabilities.resources?.subscribe == true)
        #expect(capabilities.tools?.listChanged == false)

        let encoder = JSONEncoder()
        let data = try encoder.encode(capabilities)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ServerCapabilities.self, from: data)

        #expect(decoded.resources?.subscribe == true)
        #expect(decoded.tools?.listChanged == false)
    }

    @Test("InitializeRequest has correct structure")
    func initializeRequest() throws {
        let clientInfo = Implementation(name: "test-client", version: "0.1.0")
        let capabilities = ClientCapabilities()

        let request = InitializeRequest(
            protocolVersion: MCPProtocolVersion,
            capabilities: capabilities,
            clientInfo: clientInfo
        )

        #expect(request.method == "initialize")
        #expect(request.params.protocolVersion == MCPProtocolVersion)
        #expect(request.params.clientInfo.name == "test-client")

        // Verify it encodes
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        #expect(!data.isEmpty)
    }

    @Test("InitializeResult has correct structure")
    func initializeResult() throws {
        let serverInfo = Implementation(name: "cupertino-mcp", version: "1.0.0")
        let capabilities = ServerCapabilities(
            resources: ServerCapabilities.ResourcesCapability(subscribe: false)
        )

        let result = InitializeResult(
            protocolVersion: MCPProtocolVersion,
            capabilities: capabilities,
            serverInfo: serverInfo,
            instructions: "Welcome to Cupertino MCP"
        )

        #expect(result.protocolVersion == MCPProtocolVersion)
        #expect(result.serverInfo.name == "cupertino-mcp")
        #expect(result.instructions == "Welcome to Cupertino MCP")

        // Verify Codable
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InitializeResult.self, from: data)

        #expect(decoded.serverInfo.name == "cupertino-mcp")
    }
}

// MARK: - MCP Server Tests

@Suite("MCP Server")
struct MCPServerTests {
    @Test("Server initializes with correct info")
    func serverInitialization() async {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        // Server should be created successfully (if this compiles, it worked)
        _ = server
    }

    @Test("Server can register resource provider")
    func registerResourceProvider() async {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let provider = TestResourceProvider()

        await server.registerResourceProvider(provider)
        // If this doesn't crash, registration worked
    }

    @Test("Server can register tool provider")
    func registerToolProvider() async {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let provider = TestToolProvider()

        await server.registerToolProvider(provider)
        // If this doesn't crash, registration worked
    }

    @Test("Server can register prompt provider")
    func registerPromptProvider() async {
        let server = MCPServer(name: "test-server", version: "1.0.0")
        let provider = TestPromptProvider()

        await server.registerPromptProvider(provider)
        // If this doesn't crash, registration worked
    }
}

// MARK: - Test Helpers

/// Mock resource provider for testing
struct TestResourceProvider: ResourceProvider {
    func listResources(cursor: String?) async throws -> ListResourcesResult {
        ListResourcesResult(resources: [])
    }

    func readResource(uri: String) async throws -> ReadResourceResult {
        let textResourceContents = TextResourceContents(
            uri: uri,
            mimeType: "text/plain",
            text: "test content"
        )
        let contents = ResourceContents.text(textResourceContents)
        return ReadResourceResult(contents: [contents])
    }
}

/// Mock tool provider for testing
struct TestToolProvider: ToolProvider {
    func listTools(cursor: String?) async throws -> ListToolsResult {
        ListToolsResult(tools: [])
    }

    func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        let textContent = TextContent(text: "test result")
        return CallToolResult(content: [.text(textContent)])
    }
}

/// Mock prompt provider for testing
struct TestPromptProvider: PromptProvider {
    func listPrompts(cursor: String?) async throws -> ListPromptsResult {
        ListPromptsResult(prompts: [])
    }

    func getPrompt(name: String, arguments: [String: String]?) async throws -> GetPromptResult {
        let textContent = TextContent(text: "test prompt")
        let message = PromptMessage(role: .user, content: .text(textContent))
        return GetPromptResult(messages: [message])
    }
}
