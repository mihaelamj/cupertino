import Foundation

// The MCP / MCP.Core / MCP.Core.Protocols anchor + all wire-format types are
// owned by SwiftMCPCore; the Server + Transport runtime and the provider seams
// (Resource/Tool/Prompt provider + ProviderCapabilities) are owned by
// SwiftMCPServer, lifted out of this package's former Core/Server +
// Core/Transport. SwiftMCPServer @_exported-imports SwiftMCPCore, so this one
// re-export surfaces BOTH the runtime AND, transitively, MCP.Core.Protocols.*
// to every `import MCPCore` consumer unchanged. SwiftMCPServer also declares
// the `MCP.Core.Transport` sub-namespace itself, so cupertino no longer
// re-introduces it here.
@_exported import SwiftMCPServer
