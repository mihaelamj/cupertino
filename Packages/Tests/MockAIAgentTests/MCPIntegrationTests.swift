import Foundation
@testable import MCP
import Testing
@testable import TestSupport

// MARK: - MCP Integration Tests

/// End-to-end integration tests for MCP stdio communication
/// These tests verify real client-server interaction over stdio pipes
/// Tagged as .integration because they spawn actual processes

// MARK: - Integration Test Suite

@Suite("MCP Integration Tests", .tags(.integration, .slow))
struct MCPIntegrationTests {
    // MARK: - Cupertino Server Tests (Swift-only, no Node.js)

    @Test("Initialize handshake with cupertino server")
    func cupertinoServerInitialize() async throws {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ".build/debug/cupertino")
        process.arguments = ["serve"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Give server time to start
        try await Task.sleep(for: .milliseconds(500))

        // Send initialize request (compact JSON + newline)
        let protocolVersion = MCPProtocolVersionsSupported.sorted().first ?? MCPProtocolVersion
        let initRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\(protocolVersion)","capabilities":{"roots":{"listChanged":true}},"clientInfo":{"name":"Test","version":"1.0.0"}}}\n
        """

        stdinPipe.fileHandleForWriting.write(Data(initRequest.utf8))

        // Read response with timeout
        let responseData = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw TimeoutError()
            }

            group.addTask {
                stdoutPipe.fileHandleForReading.availableData
            }

            guard let result = try await group.next() else {
                throw TimeoutError()
            }

            group.cancelAll()
            return result
        }

        let responseString = String(data: responseData, encoding: .utf8) ?? ""

        // Parse response
        let lines = responseString.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count >= 1, "Should receive at least one response line")

        let firstLine = String(lines[0])
        let responseJSON = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(firstLine.utf8))

        #expect(responseJSON.id == .int(1))

        // Decode result as InitializeResult
        let resultData = try JSONEncoder().encode(responseJSON.result)
        let initResult = try JSONDecoder().decode(InitializeResult.self, from: resultData)

        #expect(MCPProtocolVersionsSupported.contains(initResult.protocolVersion))
        #expect(initResult.serverInfo.name == "cupertino")

        // Cleanup
        process.terminate()
        process.waitUntilExit()
        #else
        // Skip on non-macOS platforms
        #endif
    }

    @Test("List tools from cupertino server")
    func cupertinoServerListTools() async throws {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ".build/debug/cupertino")
        process.arguments = ["serve"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe

        try process.run()
        try await Task.sleep(for: .milliseconds(500))

        // Initialize first
        let protocolVersion = MCPProtocolVersionsSupported.sorted().first ?? MCPProtocolVersion
        let initRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\(protocolVersion)","capabilities":{},"clientInfo":{"name":"Test","version":"1.0.0"}}}\n
        """
        stdinPipe.fileHandleForWriting.write(Data(initRequest.utf8))

        // Wait for init response
        try await Task.sleep(for: .milliseconds(500))

        // List tools
        let toolsRequest = """
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n
        """
        stdinPipe.fileHandleForWriting.write(Data(toolsRequest.utf8))

        try await Task.sleep(for: .milliseconds(500))

        let responseData = stdoutPipe.fileHandleForReading.availableData
        let responseString = String(data: responseData, encoding: .utf8) ?? ""

        let lines = responseString.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count >= 2, "Should receive init + tools responses")

        // Find the tools/list response (id: 2)
        let toolsLine = lines.first { $0.contains("\"id\":2") }
        #expect(toolsLine != nil, "Should find tools/list response")

        if let toolsLine {
            let toolsResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(String(toolsLine).utf8))
            let resultData = try JSONEncoder().encode(toolsResponse.result)
            let toolsResult = try JSONDecoder().decode(ListToolsResult.self, from: resultData)

            // Cupertino exposes tools based on available databases:
            // - Without search DB: 4 tools (search, list_samples, read_sample, read_sample_file)
            // - With search DB: 10 tools (adds read_document, list_frameworks, search_symbols, etc.)
            #expect(toolsResult.tools.count >= 4, "Should have at least sample code tools")
            #expect(toolsResult.tools.contains { $0.name == "search" })
            #expect(toolsResult.tools.contains { $0.name == "list_samples" })
        }

        process.terminate()
        process.waitUntilExit()
        #else
        // Skip on non-macOS platforms
        #endif
    }

    // MARK: - Error Handling Tests

    @Test("Handles server that never starts")
    func serverNeverStarts() async throws {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["nonexistent-command-xyz123"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Try to run nonexistent command - Process.run() may not throw
        // but the command will fail when executed
        try process.run()

        // Wait a bit and check if it's still running
        try await Task.sleep(for: .milliseconds(100))

        // Process should have exited with error
        #expect(!process.isRunning || process.terminationStatus != 0)

        process.terminate()
        #else
        // Skip on non-macOS platforms
        #endif
    }

    @Test("Handles malformed JSON from server")
    func malformedJSONResponse() async throws {
        // Simulate receiving malformed JSON
        let malformedResponse = "not valid json\n"

        #expect(throws: Error.self) {
            let data = Data(malformedResponse.utf8)
            _ = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        }
    }

    @Test("Handles incomplete JSON in stream")
    func incompleteJSON() async throws {
        // Simulate partial JSON without newline
        let partialJSON = "{\"jsonrpc\":\"2.0\",\"id\":1"

        // Should not have a complete line (split returns array with the original string)
        let lines = partialJSON.split(separator: "\n", omittingEmptySubsequences: true)
        // But since there's no newline, we get the partial data as one element
        // In real implementation, this wouldn't be processed until newline arrives
        #expect(!partialJSON.contains("\n"), "Partial JSON should not have newline")
    }

    // MARK: - Protocol Compliance Tests

    @Test("Server rejects pretty-printed JSON")
    func prettyPrintedRejection() async throws {
        // Demonstrate that multi-line JSON violates the protocol
        let prettyJSON = """
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "initialize"
        }
        """

        // Count newlines - should have many
        let newlineCount = prettyJSON.filter { $0 == "\n" }.count
        #expect(newlineCount > 1, "Pretty-printed JSON has embedded newlines")

        // This would fail in a real MCP server because it reads line-by-line
        // The server would only see the first line: "{"
        let firstLine = prettyJSON.split(separator: "\n", omittingEmptySubsequences: true).first!
        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(String(firstLine).utf8))
        }
    }

    @Test("Compact JSON is accepted")
    func compactJSONAcceptance() throws {
        let compactJSON = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
        """

        // Should have no embedded newlines
        #expect(!compactJSON.contains("\n"))

        // Should parse successfully
        let data = Data(compactJSON.utf8)
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        #expect(request.method == "initialize")
    }

    @Test("Messages with trailing newline are framed correctly")
    func correctFraming() {
        let message1 = "{\"id\":1}\n"
        let message2 = "{\"id\":2}\n"
        let stream = message1 + message2

        let lines = stream.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        #expect(String(lines[0]) == "{\"id\":1}")
        #expect(String(lines[1]) == "{\"id\":2}")
    }

    // MARK: - Stress Tests

    @Test("Handles rapid sequence of messages")
    func rapidMessages() throws {
        var stream = ""
        for idx in 1...100 {
            stream += "{\"jsonrpc\":\"2.0\",\"id\":\(idx),\"result\":{}}\n"
        }

        let lines = stream.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 100)

        // All should parse successfully
        for (index, line) in lines.enumerated() {
            let data = Data(String(line).utf8)
            let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
            #expect(response.id == .int(index + 1))
        }
    }

    @Test("Handles large JSON payload")
    func largePayload() throws {
        // Create a large tool result with many entities
        var entities: [[String: String]] = []
        for idx in 1...1000 {
            entities.append([
                "name": "Entity \(idx)",
                "type": "test",
                "value": String(repeating: "x", count: 100),
            ])
        }

        let largeResult = ["entities": entities]
        let resultData = try JSONEncoder().encode(largeResult)

        // Compact JSON should still be single-line
        let json = String(data: resultData, encoding: .utf8)!
        #expect(!json.contains("\n"))

        // Should be large (>100KB)
        #expect(json.count > 100000)
    }
}

// MARK: - Helper Types

struct TimeoutError: Error {}
