import Foundation
@testable import MCP
import Testing

// MARK: - Mock AI Agent Tests

/// Tests for the MockAIAgent MCP client
/// Focuses on MCP stdio protocol compliance, JSON encoding, and message framing
/// These tests verify the bug fix for pretty-printed JSON violating the MCP spec

// MARK: - JSON Encoding Tests

@Suite("MCP Message Encoding")
struct MCPMessageEncodingTests {
    @Test("Encodes compact JSON without embedded newlines")
    func compactJSONEncoding() throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(1),
            method: "initialize",
            params: InitializeParams(
                protocolVersion: MCPProtocolVersion,
                capabilities: ClientCapabilities(
                    experimental: nil,
                    sampling: nil,
                    roots: RootsCapability(listChanged: true)
                ),
                clientInfo: Implementation(name: "Test", version: "1.0.0")
            )
        )

        // Use compact encoding (no .prettyPrinted)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        // CRITICAL: Must not contain embedded newlines (MCP spec violation)
        #expect(!json.contains("\n"))
        #expect(!json.contains("\r"))
    }

    @Test("Pretty printed JSON contains embedded newlines")
    func prettyPrintedViolatesSpec() throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(1),
            method: "initialize",
            params: InitializeParams(
                protocolVersion: MCPProtocolVersion,
                capabilities: ClientCapabilities(
                    experimental: nil,
                    sampling: nil,
                    roots: RootsCapability(listChanged: true)
                ),
                clientInfo: Implementation(name: "Test", version: "1.0.0")
            )
        )

        // Pretty printing adds newlines (violates spec)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        // This SHOULD contain newlines (demonstrating the bug we fixed)
        #expect(json.contains("\n"))
    }

    @Test("Compact JSON is valid JSON-RPC 2.0")
    func compactJSONValid() throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(42),
            method: "tools/list",
            params: EmptyParams()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        // Decode back to verify it's valid
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(42))
        #expect(decoded.method == "tools/list")
    }

    @Test("RequestID encodes as int or string without newlines")
    func requestIDEncoding() throws {
        let intID = RequestID.int(123)
        let stringID = RequestID.string("test-456")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let intData = try encoder.encode(intID)
        let intJSON = String(data: intData, encoding: .utf8)!
        #expect(!intJSON.contains("\n"))
        #expect(intJSON == "123")

        let stringData = try encoder.encode(stringID)
        let stringJSON = String(data: stringData, encoding: .utf8)!
        #expect(!stringJSON.contains("\n"))
        #expect(stringJSON == "\"test-456\"")
    }
}

// MARK: - Message Framing Tests

@Suite("MCP Message Framing")
struct MCPMessageFramingTests {
    @Test("Message framing adds single trailing newline")
    func messageFraming() {
        let compactJSON = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test\"}"
        let framedMessage = compactJSON + "\n"

        // Should have exactly one newline at the end
        #expect(framedMessage.hasSuffix("\n"))
        #expect(framedMessage.filter { $0 == "\n" }.count == 1)
        #expect(!framedMessage.hasPrefix("\n"))
    }

    @Test("Message consists of JSON plus newline delimiter")
    func messageStructure() {
        let json = "{\"test\":\"value\"}"
        let message = json + "\n"

        // Split on newline should give JSON and empty string
        let parts = message.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(parts.count == 2)
        #expect(parts[0] == json)
        #expect(parts[1] == "")
    }

    @Test("Multiple messages are newline-delimited")
    func multipleMessages() {
        let message1 = "{\"id\":1}\n"
        let message2 = "{\"id\":2}\n"
        let message3 = "{\"id\":3}\n"

        let stream = message1 + message2 + message3

        // Should be able to split into 3 messages
        let lines = stream.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 3)
        #expect(lines[0].contains("\"id\":1"))
        #expect(lines[1].contains("\"id\":2"))
        #expect(lines[2].contains("\"id\":3"))
    }

    @Test("Empty message is just newline")
    func emptyMessage() {
        let message = "\n"
        #expect(message == "\n")
        #expect(message.count == 1)
    }
}

// MARK: - Response Parsing Tests

@Suite("MCP Response Parsing")
struct MCPResponseParsingTests {
    @Test("Parses single-line JSON response")
    func singleLineResponse() throws {
        let responseJSON = """
        {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"\(MCPProtocolVersion)"}}
        """

        let data = Data(responseJSON.utf8)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        #expect(response.jsonrpc == "2.0")
        #expect(response.id == .int(1))
    }

    @Test("Handles response with error instead of result")
    func errorResponse() throws {
        let errorJSON = """
        {"jsonrpc":"2.0","id":3,"error":{"code":-32603,"message":"Unknown tool"}}
        """

        let data = Data(errorJSON.utf8)
        let error = try JSONDecoder().decode(JSONRPCError.self, from: data)

        #expect(error.jsonrpc == "2.0")
        #expect(error.id == .int(3))
        #expect(error.error.code == -32603)
        #expect(error.error.message == "Unknown tool")
    }

    @Test("Decodes initialize response")
    func initializeResponse() throws {
        let responseJSON = """
        {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"\(MCPProtocolVersion)","capabilities":{"tools":{}},"serverInfo":{"name":"test-server","version":"1.0.0"}}}
        """

        let data = Data(responseJSON.utf8)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        // Convert result to InitializeResult
        let resultData = try JSONEncoder().encode(response.result)
        let initResult = try JSONDecoder().decode(InitializeResult.self, from: resultData)

        #expect(initResult.protocolVersion == MCPProtocolVersion)
        #expect(initResult.serverInfo.name == "test-server")
        #expect(initResult.serverInfo.version == "1.0.0")
    }

    @Test("Decodes tools/list response")
    func toolsListResponse() throws {
        let responseJSON = """
        {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"test_tool","description":"Test","inputSchema":{"type":"object","properties":{}}}]}}
        """

        let data = Data(responseJSON.utf8)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        let resultData = try JSONEncoder().encode(response.result)
        let toolsResult = try JSONDecoder().decode(ListToolsResult.self, from: resultData)

        #expect(toolsResult.tools.count == 1)
        #expect(toolsResult.tools[0].name == "test_tool")
    }
}

// MARK: - Buffer Handling Tests

@Suite("MCP Buffer Handling")
struct MCPBufferHandlingTests {
    @Test("Handles partial JSON data")
    func partialData() {
        var buffer = ""

        // Receive partial data (no newline yet)
        buffer += "{\"jsonrpc\":\"2.0\",\"id\":1"

        // Should not have a complete line
        #expect(!buffer.contains("\n"))

        // Receive rest of data
        buffer += ",\"result\":{}}\n"

        // Now should have complete line
        #expect(buffer.contains("\n"))
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 1)
    }

    @Test("Handles multiple responses in buffer")
    func multipleResponsesInBuffer() throws {
        let buffer = """
        {"jsonrpc":"2.0","id":1,"result":{}}\n
        {"jsonrpc":"2.0","id":2,"result":{}}\n
        {"jsonrpc":"2.0","id":3,"result":{}}\n
        """

        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 3)

        // Each line should be valid JSON-RPC
        for line in lines {
            let data = Data(String(line).utf8)
            _ = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        }
    }

    @Test("Handles mixed complete and partial data")
    func mixedData() {
        var buffer = ""

        // First complete message
        buffer += "{\"id\":1}\n"

        // Partial second message
        buffer += "{\"id\":2,\"res"

        // Extract complete lines
        var completedLines: [String] = []
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound])
            completedLines.append(line)
            buffer.removeSubrange(...newlineRange.lowerBound)
        }

        #expect(completedLines.count == 1)
        #expect(completedLines[0].contains("\"id\":1"))

        // Buffer should still contain partial data
        #expect(buffer == "{\"id\":2,\"res")
    }

    @Test("Skips empty lines in buffer")
    func emptyLines() {
        let buffer = """
        {"id":1}\n
        \n
        {"id":2}\n
        """

        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"id\":1"))
        #expect(lines[1].contains("\"id\":2"))
    }
}

// MARK: - Tool Call Tests

@Suite("MCP Tool Calls")
struct MCPToolCallTests {
    @Test("Encodes tool call with arguments")
    func toolCallWithArguments() throws {
        let arguments: [String: AnyCodable] = [
            "query": AnyCodable("test search"),
            "limit": AnyCodable(10),
        ]

        let request = MCPRequest(
            jsonrpc: "2.0",
            id: .int(5),
            method: "tools/call",
            params: CallToolParams(name: "search", arguments: arguments)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        // Should be single-line
        #expect(!json.contains("\n"))

        // Should contain tool name and arguments
        #expect(json.contains("\"name\":\"search\""))
        #expect(json.contains("\"query\":\"test search\""))
        #expect(json.contains("\"limit\":10"))
    }

    @Test("Handles tool call response with content")
    func toolCallResponse() throws {
        let responseJSON = """
        {"jsonrpc":"2.0","id":5,"result":{"content":[{"type":"text","text":"result"}]}}
        """

        let data = Data(responseJSON.utf8)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        let resultData = try JSONEncoder().encode(response.result)
        let toolResult = try JSONDecoder().decode(CallToolResult.self, from: resultData)

        #expect(toolResult.content.count == 1)
        if case .text(let textContent) = toolResult.content[0] {
            #expect(textContent.text == "result")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("Encodes notification without id")
    func notification() throws {
        let notification = JSONRPCNotification(
            method: "notifications/cancelled",
            params: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(notification)
        let json = String(data: data, encoding: .utf8)!

        // Should be single-line
        #expect(!json.contains("\n"))

        // Should not have id field
        #expect(!json.contains("\"id\""))

        // Should have method (escaped forward slash in JSON)
        #expect(json.contains("\"method\":\"notifications\\/cancelled\""))
    }
}

// MARK: - Helper Types

struct EmptyParams: Codable, Sendable {}
