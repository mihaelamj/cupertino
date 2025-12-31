// MARK: - MCPShared Package

//
// Core Model Context Protocol types and JSON-RPC 2.0 implementation.
// This package contains all protocol messages, types, and structures
// defined by the MCP specification (2025-06-18).
//
// Zero dependencies - Foundation layer package.

@_exported import struct Foundation.Data
@_exported import struct Foundation.URL
@_exported import struct Foundation.UUID

// Re-export all public types
// This allows users to: import MCPShared

/// Current MCP Protocol Version
public let protocolVersion = MCPProtocolVersion

// MARK: - Usage Example

/*
 // Create an initialize request
 let initRequest = InitializeRequest(
     protocolVersion: MCPProtocolVersion,
     capabilities: ClientCapabilities(),
     clientInfo: Implementation(name: "MyClient", version: "1.0.0")
 )

 // Create a resource
 let resource = Resource(
     uri: "file:///docs/intro.md",
     name: "Introduction",
     description: "Getting started guide",
     mimeType: "text/markdown"
 )

 // Create text content
 let textContent = ContentBlock.text(TextContent(text: "Hello, world!"))
 */
