import Foundation

// SPIKE (#1167, spike branch only): the MCP / MCP.Core / MCP.Core.Protocols
// anchor + all wire-format types are now owned by the extracted SwiftMCPCore
// (re-exported below so `import MCPCore` consumers still see `MCP.Core.Protocols.*`
// unchanged). cupertino keeps only the Server + Transport layers, which extend
// the kit's `MCP.Core`.
@_exported import SwiftMCPCore

// MARK: - MCP.Core.Transport sub-namespace

/// The kit's `SwiftMCPCore` declares `MCP.Core.Protocols` but NOT
/// `MCP.Core.Transport` (it ships transport as separate modules). cupertino's
/// own transport layer (Channel / Message / Failure / Stdio) extends this
/// re-introduced sub-namespace on the kit's `MCP.Core` anchor.
extension MCP.Core {
    public enum Transport {}
}
