import Foundation
@testable import MCP
@testable import SampleIndex
import SharedConstants
@testable import SharedCore
import Testing
@testable import TestSupport

// MARK: - MCP Integration Tests

// End-to-end integration tests for MCP stdio communication
// These tests verify real client-server interaction over stdio pipes
// Tagged as .integration because they spawn actual processes

// MARK: - Integration Test Suite

@Suite("MCP Integration Tests", .tags(.integration, .slow), .serialized)
struct MCPIntegrationTests {
    // MARK: - Cupertino Server Tests (Swift-only, no Node.js)

    @Test("Initialize handshake with cupertino server")
    func cupertinoServerInitialize() async throws {
        #if os(macOS)
        // Side-step the debug build's `cupertino.config.json` redirect to
        // `~/.cupertino-dev/` and ensure the server has a samples.db so it
        // doesn't exit with the welcome guide. See helper docs.
        let fixture = try CupertinoServerFixture()
        defer { fixture.cleanup() }

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
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        // Give server time to start (binary fork + DB open takes a few hundred ms)
        try await Task.sleep(for: .milliseconds(500))

        // If the server died during startup (e.g., the welcome-guide exit
        // path), the write below would otherwise SIGPIPE the test process.
        guard process.isRunning else {
            let stderr = String(data: stderrPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            Issue.record("cupertino serve exited before initialize could be sent. stderr:\n\(stderr)")
            return
        }

        // Send initialize request (compact JSON + newline). Use the throwing
        // write API so a broken pipe surfaces as a Swift error instead of
        // SIGPIPE'ing the test bundle.
        let protocolVersion = MCPProtocolVersionsSupported.sorted().first ?? MCPProtocolVersion
        let initRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\(
            protocolVersion
        )","capabilities":{"roots":{"listChanged":true}},"clientInfo":{"name":"Test","version":"1.0.0"}}}\n
        """
        try stdinPipe.fileHandleForWriting.write(contentsOf: Data(initRequest.utf8))

        // Poll stdout until we see the id:1 response or the deadline expires.
        // Replaces an earlier TaskGroup-with-timeout pattern that could hang
        // because synchronous `availableData` ignores Task cancellation.
        let buffer = try await readUntil(
            stdout: stdoutPipe,
            stderr: stderrPipe,
            until: { $0.contains("\"id\":1") },
            deadline: 30
        )

        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: true)
        let firstLine = try #require(lines.first.map(String.init), "Should receive at least one response line")
        let responseJSON = try JSONDecoder().decode(MCP.Core.Protocols.JSONRPCResponse.self, from: Data(firstLine.utf8))

        #expect(responseJSON.id == .int(1))

        let resultData = try JSONEncoder().encode(responseJSON.result)
        let initResult = try JSONDecoder().decode(MCP.Core.Protocols.InitializeResult.self, from: resultData)

        #expect(MCPProtocolVersionsSupported.contains(initResult.protocolVersion))
        #expect(initResult.serverInfo.name == "cupertino")
        #else
        // Skip on non-macOS platforms
        #endif
    }

    @Test("List tools from cupertino server")
    func cupertinoServerListTools() async throws {
        #if os(macOS)
        let fixture = try CupertinoServerFixture()
        defer { fixture.cleanup() }

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
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        try await Task.sleep(for: .milliseconds(500))

        guard process.isRunning else {
            let stderr = String(data: stderrPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            Issue.record("cupertino serve exited before requests could be sent. stderr:\n\(stderr)")
            return
        }

        // Pipeline both requests up front; the server reads them sequentially
        // and writes one response per request to stdout.
        let protocolVersion = MCPProtocolVersionsSupported.sorted().first ?? MCPProtocolVersion
        let initRequest = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\(protocolVersion)","capabilities":{},"clientInfo":{"name":"Test","version":"1.0.0"}}}\n
        """
        let toolsRequest = """
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n
        """
        try stdinPipe.fileHandleForWriting.write(contentsOf: Data(initRequest.utf8))
        try stdinPipe.fileHandleForWriting.write(contentsOf: Data(toolsRequest.utf8))

        // 30s deadline: the server has to read its DBs and initialise a few
        // MB of indexed state before emitting tools/list. On a busy box the
        // process-fork + read can exceed 10s; 30s is a tight upper bound on
        // a healthy machine.
        let buffer = try await readUntil(
            stdout: stdoutPipe,
            stderr: stderrPipe,
            until: { $0.contains("\"id\":1") && $0.contains("\"id\":2") },
            deadline: 30
        )

        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count >= 2, "Should receive init + tools responses before the 30s deadline")

        let toolsLine = try #require(
            lines.first { $0.contains("\"id\":2") },
            "Should find tools/list response"
        )

        let toolsResponse = try JSONDecoder().decode(MCP.Core.Protocols.JSONRPCResponse.self, from: Data(String(toolsLine).utf8))
        let resultData = try JSONEncoder().encode(toolsResponse.result)
        let toolsResult = try JSONDecoder().decode(MCP.Core.Protocols.ListToolsResult.self, from: resultData)

        // Cupertino exposes tools based on available databases:
        // - Without search DB: 4 tools (search, list_samples, read_sample, read_sample_file)
        // - With search DB: 10 tools (adds read_document, list_frameworks, search_symbols, etc.)
        #expect(toolsResult.tools.count >= 4, "Should have at least sample code tools")
        #expect(toolsResult.tools.contains { $0.name == "search" })
        #expect(toolsResult.tools.contains { $0.name == "list_samples" })
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
    func malformedJSONResponse() throws {
        // Simulate receiving malformed JSON
        let malformedResponse = "not valid json\n"

        #expect(throws: Error.self) {
            let data = Data(malformedResponse.utf8)
            _ = try JSONDecoder().decode(MCP.Core.Protocols.JSONRPCResponse.self, from: data)
        }
    }

    @Test("Handles incomplete JSON in stream")
    func incompleteJSON() {
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
    func prettyPrintedRejection() throws {
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
        let firstLine = try #require(prettyJSON.split(separator: "\n", omittingEmptySubsequences: true).first)
        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(MCP.Core.Protocols.JSONRPCRequest.self, from: Data(String(firstLine).utf8))
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
        let request = try JSONDecoder().decode(MCP.Core.Protocols.JSONRPCRequest.self, from: data)
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
            let response = try JSONDecoder().decode(MCP.Core.Protocols.JSONRPCResponse.self, from: data)
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
        let json = try #require(String(data: resultData, encoding: .utf8))
        #expect(!json.contains("\n"))

        // Should be large (>100KB)
        #expect(json.count > 100000)
    }
}

// MARK: - Helper Types

struct TimeoutError: Error {}

// MARK: - Integration Test Fixture

/// Sets up the local environment so the spawned `cupertino serve` binary
/// finds enough state to start without bailing out with the welcome guide.
///
/// Two pieces of background:
///
/// 1. The debug-build binary at `.build/debug/cupertino` ships with a
///    sibling `cupertino.config.json` that overrides `baseDirectory` to
///    `~/.cupertino-dev/`. That keeps day-to-day development data away
///    from the production `~/.cupertino/`. Integration tests run inside a
///    test bundle where `Bundle.main.executableURL` is the test runner
///    (not cupertino), so `Shared.Constants.BinaryConfig.shared` resolves to
///    `~/.cupertino/`. The path mismatch makes the test create a
///    fixture DB at `~/.cupertino/samples.db` while the spawned cupertino
///    looks for `~/.cupertino-dev/samples.db`. This fixture moves the
///    config aside for the duration of the test so both processes agree
///    on `~/.cupertino/`.
///
/// 2. `Command.Serve.checkForData` exits with the welcome-guide message
///    if neither `~/.cupertino/samples.db` nor `~/.cupertino/search.db`
///    exists. Creating an empty samples.db (the same code path
///    `cupertino save --samples` uses) is enough to make
///    `checkForData()` return `true`. We don't need a populated DB for
///    these protocol-framing tests.
///
/// Cleanup happens via `defer { fixture.cleanup() }` in each test. We
/// avoid `deinit` because the suite's `.serialized` trait combined with
/// Swift Testing's per-test struct re-instantiation makes explicit
/// teardown clearer than relying on ARC timing.
struct CupertinoServerFixture {
    private let configURL: URL
    private let savedConfig: Data?

    init() throws {
        configURL = URL(fileURLWithPath: ".build/debug/cupertino.config.json")
        savedConfig = try? Data(contentsOf: configURL)
        if savedConfig != nil {
            try? FileManager.default.removeItem(at: configURL)
        }

        // Ensure samples.db exists at the production path so
        // `Command.Serve.checkForData()` sees data. Empty schema is fine —
        // these tests check MCP framing, not query results.
        let sampleDBPath = SampleIndex.defaultDatabasePath
        if !FileManager.default.fileExists(atPath: sampleDBPath.path) {
            // Synchronous setup of the schema via a blocking task hop.
            // Swift Testing's @Test functions are async, so we can spin up
            // a Task here, but we need the DB written before the spawned
            // cupertino reads it. Use a dispatch semaphore.
            let sem = DispatchSemaphore(value: 0)
            Task {
                if let db = try? await SampleIndex.Database(dbPath: sampleDBPath) {
                    await db.disconnect()
                }
                sem.signal()
            }
            sem.wait()
        }
    }

    func cleanup() {
        // Restore the dev config so subsequent non-test invocations of
        // cupertino keep using `~/.cupertino-dev/` like the developer
        // expects.
        if let savedConfig {
            try? savedConfig.write(to: configURL)
        }
    }
}

/// Polls `stdout` (and surfaces any concurrent `stderr` content if the
/// deadline expires) until `predicate(buffer)` becomes true or the deadline
/// is reached. Returns the accumulated buffer.
///
/// Why polling rather than `withThrowingTaskGroup` + `availableData`:
/// `FileHandle.availableData` is a synchronous call that blocks when no
/// data is available. Wrapping it in a Task and racing against a sleep
/// works for the happy path, but if the sleep wins the race the
/// `availableData` task can't be cancelled (cancellation requires a
/// Swift-Concurrency suspension point, which the synchronous read doesn't
/// provide). The test bundle then hangs in the implicit "wait for all
/// child tasks" at the end of the TaskGroup. Polling with a 50 ms sleep
/// in between reads side-steps the hang — every iteration is a real
/// suspension point that respects cancellation and timeouts.
func readUntil(
    stdout: Pipe,
    stderr: Pipe,
    until predicate: (String) -> Bool,
    deadline seconds: TimeInterval
) async throws -> String {
    let deadline = Date().addingTimeInterval(seconds)
    var buffer = ""
    while Date() < deadline {
        let chunk = stdout.fileHandleForReading.availableData
        if chunk.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            continue
        }
        if let piece = String(data: chunk, encoding: .utf8) {
            buffer += piece
        }
        if predicate(buffer) {
            return buffer
        }
    }
    let stderrText = String(data: stderr.fileHandleForReading.availableData, encoding: .utf8) ?? ""
    Issue.record("Read deadline (\(seconds)s) expired waiting for predicate. stdout:\n\(buffer)\nstderr:\n\(stderrText)")
    return buffer
}
