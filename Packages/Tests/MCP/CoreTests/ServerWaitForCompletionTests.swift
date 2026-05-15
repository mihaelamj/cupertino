import Foundation
@testable import MCPCore
import Testing

// Regression suite for [#618](https://github.com/mihaelamj/cupertino/issues/618)
// — `cupertino serve` must exit when its transport's `messages` stream
// finishes. The fix added `MCP.Core.Server.waitForCompletion()` which
// awaits the server's internal `messageTask`. `processMessages` ends
// when the transport's `AsyncStream<Message>` finishes (the stdio
// transport finishes the stream on stdin EOF), so the CLI's
// `await server.waitForCompletion()` returns and the process exits.
//
// Pre-fix the CLI parked on `while true { Task.sleep(.seconds(60)) }`
// and never noticed transport EOF, leaving the process alive forever
// after AI-agent clients (Claude Desktop, Cursor, Codex MCP) closed
// stdin. Studio's heartbeat machine had been hunting stray
// `cupertino serve` procs for two days; this was the root cause.

// MARK: - In-memory transport that exposes a finish hook

private actor CloseableTransport: MCP.Core.Transport.Channel {
    private let inboundStream: AsyncStream<MCP.Core.Transport.Message>
    private let inboundContinuation: AsyncStream<MCP.Core.Transport.Message>.Continuation
    private var sent: [MCP.Core.Transport.Message] = []
    private var started = false

    init() {
        var continuation: AsyncStream<MCP.Core.Transport.Message>.Continuation!
        inboundStream = AsyncStream<MCP.Core.Transport.Message> { cont in
            continuation = cont
        }
        inboundContinuation = continuation
    }

    func deliver(_ message: MCP.Core.Transport.Message) {
        inboundContinuation.yield(message)
    }

    /// Mirrors `Stdio.readLoop`'s reaction to stdin EOF: when the
    /// underlying byte stream ends, the read loop falls through and
    /// the message continuation finishes. Tests call this to simulate
    /// the AI-agent client closing its stdin side.
    func closeInbound() {
        inboundContinuation.finish()
    }

    func sentMessages() -> [MCP.Core.Transport.Message] {
        sent
    }

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
        get async { inboundStream }
    }

    var isConnected: Bool {
        started
    }
}

// MARK: - Suite

@Suite("#618 server exits when transport stream closes (waitForCompletion)", .serialized)
struct ServerWaitForCompletionTests {
    @Test("waitForCompletion returns when the transport finishes its messages stream (simulated stdin EOF)")
    func waitForCompletionReturnsOnTransportFinish() async throws {
        let transport = CloseableTransport()
        let server = MCP.Core.Server(name: "test-eof-server", version: "1.0.0")
        try await server.connect(transport)

        // Spawn the wait in a child task so we can race it against a
        // bounded timeout. The child returns true if waitForCompletion
        // resolved within the deadline, false if we had to time out.
        let waitTask = Task<Bool, Never> {
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await server.waitForCompletion()
                    return true
                }
                group.addTask {
                    // 3 s upper bound. Real EOF-detection runs in microseconds;
                    // anything past 3 s means waitForCompletion is hung.
                    try? await Task.sleep(for: .seconds(3))
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
        }

        // Give the message task a moment to start processing the empty
        // stream — the server's `processMessages` enters the `for await`
        // loop immediately, but we want to avoid racing the spawn.
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate stdin EOF: finish the transport's messages stream.
        // The server's `for await message in messageStream` loop drops
        // through, `processMessages` returns, the messageTask ends, and
        // `waitForCompletion` (which awaits the task's `.value`) resolves.
        await transport.closeInbound()

        let resolved = await waitTask.value
        #expect(resolved, "server.waitForCompletion() must return within 3 s after the transport's messages stream finishes")
    }

    @Test("waitForCompletion resolves after a normal init + close cycle")
    func waitForCompletionAfterInitAndClose() async throws {
        let transport = CloseableTransport()
        let server = MCP.Core.Server(name: "test-eof-server", version: "1.0.0")
        try await server.connect(transport)

        // Deliver a real initialize request first so the server has
        // something to handle, then close.
        let initRequest = MCP.Core.Protocols.JSONRPCRequest(
            id: .int(1),
            method: MCP.Core.Protocols.Method.initialize,
            params: [
                "protocolVersion": MCP.Core.Protocols.AnyCodable("2025-06-18"),
                "capabilities": MCP.Core.Protocols.AnyCodable([String: MCP.Core.Protocols.AnyCodable]()),
                "clientInfo": MCP.Core.Protocols.AnyCodable([
                    "name": MCP.Core.Protocols.AnyCodable("probe"),
                    "version": MCP.Core.Protocols.AnyCodable("0"),
                ] as [String: MCP.Core.Protocols.AnyCodable]),
            ]
        )
        await transport.deliver(.request(initRequest))

        // Give the server a brief window to handle the initialize.
        try? await Task.sleep(for: .milliseconds(100))

        let waitTask = Task<Bool, Never> {
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await server.waitForCompletion()
                    return true
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(3))
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
        }

        await transport.closeInbound()

        let resolved = await waitTask.value
        #expect(resolved, "server.waitForCompletion() must return within 3 s of close even after handling an initialize")
    }
}
