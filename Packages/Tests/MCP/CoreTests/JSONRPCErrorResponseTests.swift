import Foundation
@testable import MCPCore
import Testing

// MARK: - #581 every id-bound request must receive a JSON-RPC frame

//
// Pre-fix, `MCP.Core.Server.handleRequest` only converted `ServerError`
// into a JSON-RPC error frame. Any other thrown error (notably the
// `LocalizedError` instances tool handlers raise for bad arguments)
// fell through, got logged to stderr, and the client request hung
// forever waiting for its id. The fix adds a catch-all branch that
// converts any thrown error into a `JSONRPCError` frame with code
// `-32602` (invalidParams) and the underlying `LocalizedError`'s
// `errorDescription` as the human-readable message.
//
// This integration test drives the real `MCP.Core.Server` through a
// proper initialize handshake using an in-memory `Transport.Channel`,
// then sends a `tools/call` whose tool provider throws a generic
// `LocalizedError`. The assertion: the server must emit a JSON-RPC
// error frame (not hang / not log-only) and the frame's code +
// message must match the contract.

// MARK: - In-memory transport double

private actor InMemoryTransport: MCP.Core.Transport.Channel {
    private let inboundStream: AsyncStream<MCP.Core.Transport.Message>
    private let inboundContinuation: AsyncStream<MCP.Core.Transport.Message>.Continuation
    private var sent: [MCP.Core.Transport.Message] = []
    private var started = false

    init() {
        var continuation: AsyncStream<MCP.Core.Transport.Message>.Continuation!
        inboundStream = AsyncStream<MCP.Core.Transport.Message> { c in
            continuation = c
        }
        inboundContinuation = continuation
    }

    func deliver(_ message: MCP.Core.Transport.Message) {
        inboundContinuation.yield(message)
    }

    func sentMessages() -> [MCP.Core.Transport.Message] {
        sent
    }

    // MARK: Channel

    func start() async throws {
        started = true
    }

    func stop() async throws {
        started = false
    }

    func send(_ message: MCP.Core.Transport.Message) async throws {
        sent.append(message)
    }

    nonisolated var messages: AsyncStream<MCP.Core.Transport.Message> {
        get async { await inboundStream }
    }

    var isConnected: Bool {
        started
    }
}

// MARK: - Tool provider that throws a non-ServerError

/// Tool provider whose `callTool` always throws a `LocalizedError` —
/// the shape that tool handlers like `read_document` raise on bad
/// arguments. Pre-#581 this would be swallowed by the server's outer
/// catch and the client request would hang.
private struct ThrowingToolProvider: MCP.Core.ToolProvider {
    struct BogusURIError: LocalizedError {
        let uri: String
        var errorDescription: String? {
            "Document not found: \(uri)"
        }
    }

    func listTools(cursor _: String?) async throws -> MCP.Core.Protocols.ListToolsResult {
        let schema = MCP.Core.Protocols.JSONSchema(
            type: "object",
            properties: ["uri": MCP.Core.Protocols.AnyCodable(["type": "string"])],
            required: ["uri"]
        )
        let tool = MCP.Core.Protocols.Tool(
            name: "read_document",
            description: "stub",
            inputSchema: schema
        )
        return MCP.Core.Protocols.ListToolsResult(tools: [tool])
    }

    func callTool(name _: String, arguments: [String: MCP.Core.Protocols.AnyCodable]?) async throws -> MCP.Core.Protocols.CallToolResult {
        let uri = arguments?["uri"]?.value as? String ?? "<unknown>"
        throw BogusURIError(uri: uri)
    }
}

// MARK: - Helpers

/// Build a proper `JSONRPCRequest` from a typed Codable payload by
/// round-tripping through JSON. Avoids the brittle dict-literal cast
/// path and matches what real MCP clients put on the wire.
private func makeRequest(id: MCP.Core.Protocols.RequestID, method: String, payload: some Codable) throws -> MCP.Core.Protocols.JSONRPCRequest {
    let encoder = JSONEncoder()
    let payloadData = try encoder.encode(payload)
    let dict = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] ?? [:]
    var params: [String: MCP.Core.Protocols.AnyCodable] = [:]
    for (key, value) in dict {
        params[key] = MCP.Core.Protocols.AnyCodable.fromAny(value)
    }
    return MCP.Core.Protocols.JSONRPCRequest(id: id, method: method, params: params)
}

extension MCP.Core.Protocols.AnyCodable {
    /// Build an `AnyCodable` from an arbitrary JSON-decoded `Any` value.
    /// Bridges the typed-payload → request-params conversion that real
    /// MCP clients perform on the wire.
    fileprivate static func fromAny(_ value: Any) -> MCP.Core.Protocols.AnyCodable {
        switch value {
        case let s as String: return MCP.Core.Protocols.AnyCodable(s)
        case let i as Int: return MCP.Core.Protocols.AnyCodable(i)
        case let d as Double: return MCP.Core.Protocols.AnyCodable(d)
        case let b as Bool: return MCP.Core.Protocols.AnyCodable(b)
        case let arr as [Any]:
            return MCP.Core.Protocols.AnyCodable(arr.map(MCP.Core.Protocols.AnyCodable.fromAny))
        case let dict as [String: Any]:
            var out: [String: MCP.Core.Protocols.AnyCodable] = [:]
            for (k, v) in dict {
                out[k] = MCP.Core.Protocols.AnyCodable.fromAny(v)
            }
            return MCP.Core.Protocols.AnyCodable(out)
        default:
            return MCP.Core.Protocols.AnyCodable(String(describing: value))
        }
    }
}

/// Poll the transport's `sentMessages()` buffer for up to `timeout`
/// seconds, succeeding when `predicate` returns true on any message.
/// Beats a flat sleep because the server's processMessages task runs
/// non-deterministically under test scheduling.
private func waitForMessage(
    on transport: InMemoryTransport,
    timeout: TimeInterval = 5.0,
    matching predicate: (MCP.Core.Transport.Message) -> Bool
) async -> MCP.Core.Transport.Message? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let sent = await transport.sentMessages()
        if let hit = sent.first(where: predicate) { return hit }
        try? await Task.sleep(for: .milliseconds(40))
    }
    return nil
}

// MARK: - Suite

@Suite("#581 server emits JSON-RPC error frame for any thrown error", .serialized)
struct JSONRPCErrorResponseTests {
    @Test("tools/call argument that throws LocalizedError → JSON-RPC error frame (not hang)")
    func toolCallErrorBecomesJSONRPCError() async throws {
        let transport = InMemoryTransport()
        let server = MCP.Core.Server(name: "test-server", version: "1.0.0")
        await server.registerToolProvider(ThrowingToolProvider())

        try await server.connect(transport)

        // 1) initialize — build a real InitializeRequest payload so the
        // server's params decoding succeeds (the brittle dict-literal
        // path failed silently in the first cut of this test).
        let initRequest = try makeRequest(
            id: .int(1),
            method: MCP.Core.Protocols.Method.initialize,
            payload: MCP.Core.Protocols.InitializeRequest.Params(
                protocolVersion: "2025-06-18",
                capabilities: MCP.Core.Protocols.ClientCapabilities(),
                clientInfo: MCP.Core.Protocols.Implementation(name: "test", version: "1.0")
            )
        )
        await transport.deliver(.request(initRequest))

        // Wait for the initialize response so we know the server is
        // ready before sending tools/call.
        let initResponse = await waitForMessage(on: transport) { msg in
            if case .response(let r) = msg, case .int(1) = r.id { return true }
            if case .error(let e) = msg, case .int(1) = e.id { return true }
            return false
        }
        try #require(initResponse != nil, "server must respond to the initialize request")
        if case .error(let e) = initResponse {
            Issue.record("initialize failed: code=\(e.error.code) message=\(e.error.message)")
            return
        }

        // 2) notifications/initialized — the spec-named ack.
        let initialized = MCP.Core.Protocols.JSONRPCNotification(
            method: "notifications/initialized",
            params: nil
        )
        await transport.deliver(.notification(initialized))

        // 3) tools/call with arguments that make the provider throw.
        let toolCall = try makeRequest(
            id: .int(2),
            method: MCP.Core.Protocols.Method.toolsCall,
            payload: MCP.Core.Protocols.CallToolRequest.Params(
                name: "read_document",
                arguments: ["uri": MCP.Core.Protocols.AnyCodable("apple-docs://nonexistent/garbage")]
            )
        )
        await transport.deliver(.request(toolCall))

        // Wait for the tools/call response — must be an error frame.
        let toolCallResponse = await waitForMessage(on: transport) { msg in
            if case .error(let e) = msg, case .int(2) = e.id { return true }
            if case .response(let r) = msg, case .int(2) = r.id { return true }
            return false
        }
        try #require(toolCallResponse != nil, "server must emit a frame for the throwing tools/call — pre-#581 it would hang")

        guard case .error(let err) = toolCallResponse else {
            Issue.record("expected JSON-RPC error frame, got success: \(String(describing: toolCallResponse))")
            return
        }
        #expect(
            err.error.code == MCP.Core.Protocols.ErrorCode.invalidParams.rawValue,
            "error code should be invalidParams (-32602), got \(err.error.code)"
        )
        #expect(
            err.error.message.contains("Document not found"),
            "error message must carry the LocalizedError.errorDescription: got '\(err.error.message)'"
        )
        #expect(
            err.error.message.contains("apple-docs://nonexistent/garbage"),
            "error message must carry the offending URI verbatim"
        )
    }
}
