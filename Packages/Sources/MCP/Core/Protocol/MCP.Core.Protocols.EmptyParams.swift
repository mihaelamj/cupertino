import Foundation

/// Empty parameter bundle for MCP JSON-RPC requests that don't carry any
/// arguments (e.g. `initialize`, `tools/list`, `resources/list`,
/// `ping`). Equivalent to `{}` on the wire.
///
/// Used as the generic `Params` argument to
/// `MCP.Core.Protocols.Request<Params>` for the no-args methods.
/// Declared once here so MCPClient, MCPSupport, MockAIAgent and any
/// future MCP consumer share the same wire shape.
extension MCP.Core.Protocols {
    public struct EmptyParams: Codable, Sendable {
        public init() {}
    }
}
