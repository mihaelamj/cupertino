// MARK: - MCPTransport Package

//
// Transport layer implementations for Model Context Protocol.
// Supports stdio (for CLI/Claude Desktop) and HTTP/SSE (for web clients).
//
// Now part of the unified MCP module

// MARK: - Usage Example

/*
 Current transport implementations:
 - StdioTransport: Standard input/output for CLI tools and Claude Desktop
 - HTTPTransport: Coming soon - HTTP with Server-Sent Events for web clients

 Example usage:
 // Create and start stdio transport
 let transport = StdioTransport()
 try await transport.start()

 // Listen for messages
 for await message in transport.messages {
     switch message {
     case .request(let req):
         print("Received request: \(req.method)")
     case .notification(let notif):
         print("Received notification: \(notif.method)")
     default:
         break
     }
 }

 // Send a response
 let response = JSONRPCResponse(
     id: .int(1),
     result: ["status": AnyCodable("ok")]
 )
 try await transport.send(.response(response))

 // Stop transport
 try await transport.stop()
 */
