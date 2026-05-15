import Foundation
@testable import MCPCore
import Testing

/// Regression suite for [#611](https://github.com/mihaelamj/cupertino/issues/611).
///
/// Pre-fix, `MCP.Core.ServerError.methodNotFound(String).message`
/// returned `"MCP.Core.Protocols.Method not found: \(method)"` — the
/// Swift namespace path `MCP.Core.Protocols.` leaked into the
/// `message` field of the JSON-RPC error frame that clients and AI
/// agents read. The other six `ServerError` cases had clean strings;
/// only this one carried the autocomplete slip.
///
/// Tests pin the exact strings for every case so a future tweak to
/// any of them is intentional, not accidental.
@Suite("MCP.Core.ServerError.message — clean human-readable strings (#611)")
struct ServerErrorMessageTests {
    @Test("methodNotFound returns 'Method not found: <name>' — no Swift namespace prefix")
    func methodNotFoundMessage() {
        let err = MCP.Core.ServerError.methodNotFound("tools/whatever")
        #expect(err.message == "Method not found: tools/whatever")
        // Negative anchor: the pre-#611 string must not creep back in.
        #expect(!err.message.contains("MCP.Core.Protocols."))
    }

    @Test("methodNotFound JSON-RPC error code stays -32601 (#611 doesn't change the wire code)")
    func methodNotFoundCodeUnchanged() {
        let err = MCP.Core.ServerError.methodNotFound("anything")
        #expect(err.code == MCP.Core.Protocols.ErrorCode.methodNotFound.rawValue)
        #expect(err.code == -32601)
    }

    @Test("Other ServerError cases stay clean")
    func otherCasesUnchanged() {
        #expect(MCP.Core.ServerError.alreadyRunning.message == "Server is already running")
        #expect(MCP.Core.ServerError.transportNotConnected.message == "Transport is not connected")
        #expect(
            MCP.Core.ServerError.notInitialized.message ==
                "Server has not been initialized. Call initialize first."
        )
        #expect(MCP.Core.ServerError.alreadyInitialized.message == "Server has already been initialized")
        #expect(MCP.Core.ServerError.invalidParams("bad").message == "Invalid parameters: bad")
        #expect(
            MCP.Core.ServerError.capabilityNotSupported("foo").message ==
                "Capability not supported: foo"
        )
        #expect(MCP.Core.ServerError.encodingFailed.message == "Failed to encode response")
    }

    @Test("LocalizedError errorDescription forwards to message")
    func localizedDescriptionForwards() {
        let err = MCP.Core.ServerError.methodNotFound("foo/bar")
        #expect(err.errorDescription == "Method not found: foo/bar")
    }
}
