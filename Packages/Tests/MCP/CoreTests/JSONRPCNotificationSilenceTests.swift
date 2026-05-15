import Foundation
@testable import MCPCore
import Testing

// Regression suite for [#613](https://github.com/mihaelamj/cupertino/issues/613)
// item 3 — JSON-RPC notifications must NOT receive a response.
//
// JSON-RPC 2.0 §4.1: "A Notification is a Request object without an
// `id` member. … The Server MUST NOT reply to a Notification, including
// those that are within a batch request." MCP layers on top of JSON-RPC
// and inherits the rule.
//
// `MCP.Core.Server.handleMessage` dispatches by message case: `.request`
// goes to `handleRequest` (which always emits a result/error frame),
// `.notification` goes to `handleNotification` (which only logs). The
// type-system enforces the split because the `JSONRPCParser` routes
// id-less frames into the `.notification` case at decode time. These
// tests pin the behaviour against future drift — if anyone changes
// `handleNotification` to send a response, the tests fail.
//
// Spec-compliant before this PR (verified by hand-probing the live
// binary with 4 notification shapes — `notifications/initialized`,
// `notifications/cancelled`, an unknown `notifications/banana`,
// and `tools/list` without an `id`). Adding the regression anchor here
// is the only artefact of #613 item 3; no source change needed.

// MARK: - Reuse the in-memory transport pattern from JSONRPCErrorResponseTests

private actor SilenceTransport: MCP.Core.Transport.Channel {
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

    func sentMessages() -> [MCP.Core.Transport.Message] {
        sent
    }

    func sentCount() -> Int {
        sent.count
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
        get async { inboundStream }
    }

    var isConnected: Bool {
        started
    }
}

// MARK: - Suite

@Suite("#613 item 3 — server does NOT reply to JSON-RPC notifications", .serialized)
struct JSONRPCNotificationSilenceTests {
    @Test("notifications/initialized produces zero response frames")
    func notificationsInitializedSilent() async throws {
        try await assertNotificationSilent(method: "notifications/initialized")
    }

    @Test("notifications/cancelled produces zero response frames")
    func notificationsCancelledSilent() async throws {
        try await assertNotificationSilent(method: "notifications/cancelled")
    }

    @Test("Unknown notifications/<arbitrary> produces zero response frames (server logs only)")
    func unknownNotificationSilent() async throws {
        try await assertNotificationSilent(method: "notifications/banana-not-a-real-thing")
    }

    @Test("Multiple notifications in a row produce zero response frames combined")
    func batchNotificationsSilent() async throws {
        let transport = SilenceTransport()
        let server = MCP.Core.Server(name: "test-silence-server", version: "1.0.0")
        try await server.connect(transport)

        // Baseline: nothing sent yet.
        let before = await transport.sentCount()
        #expect(before == 0)

        // Three different notifications, none with an id.
        await transport.deliver(.notification(MCP.Core.Protocols.JSONRPCNotification(
            method: "notifications/initialized",
            params: nil
        )))
        await transport.deliver(.notification(MCP.Core.Protocols.JSONRPCNotification(
            method: "notifications/cancelled",
            params: nil
        )))
        await transport.deliver(.notification(MCP.Core.Protocols.JSONRPCNotification(
            method: "notifications/whatever",
            params: nil
        )))

        // Give the server's processMessages task time to drain. The
        // 250 ms upper bound matches the JSONRPCErrorResponseTests
        // `waitForMessage` cadence — long enough for the dispatch loop
        // to chew through three frames if it would send anything.
        try? await Task.sleep(for: .milliseconds(250))

        let after = await transport.sentCount()
        #expect(after == 0, "server must not emit any response frames for 3 notifications; got \(after)")
    }

    // MARK: - Helper

    /// Drive the server through a single notification + wait window, then
    /// assert no message was sent on the outbound transport.
    private func assertNotificationSilent(method: String) async throws {
        let transport = SilenceTransport()
        let server = MCP.Core.Server(name: "test-silence-server", version: "1.0.0")
        try await server.connect(transport)

        let baseline = await transport.sentCount()
        #expect(baseline == 0)

        await transport.deliver(.notification(MCP.Core.Protocols.JSONRPCNotification(
            method: method,
            params: nil
        )))

        try? await Task.sleep(for: .milliseconds(250))

        let after = await transport.sentCount()
        #expect(
            after == 0,
            "server must not emit a response frame for notification '\(method)'; got \(after) frame(s)"
        )
    }
}
