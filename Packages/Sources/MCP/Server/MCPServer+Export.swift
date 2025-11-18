// MARK: - MCPServer Package

//
// High-level MCP server implementation with provider abstractions.
// Handles initialization, request routing, and protocol compliance.
//
// Now part of the unified MCP module

// MARK: - Usage Example

/*
 // Create server
 let server = MCPServer(name: "MyServer", version: "1.0.0")

 // Register a resource provider
 struct MyResourceProvider: ResourceProvider {
     func listResources(cursor: String?) async throws -> ListResourcesResult {
         let resources = [
             Resource(
                 uri: "file:///docs/intro.md",
                 name: "Introduction",
                 description: "Getting started guide",
                 mimeType: "text/markdown"
             )
         ]
         return ListResourcesResult(resources: resources)
     }

     func readResource(uri: String) async throws -> ReadResourceResult {
         let markdown = "# Introduction\n\nWelcome to the docs!"
         let contents = ResourceContents.text(
             TextResourceContents(
                 uri: uri,
                 mimeType: "text/markdown",
                 text: markdown
             )
         )
         return ReadResourceResult(contents: [contents])
     }
 }

 server.registerResourceProvider(MyResourceProvider())

 // Connect to stdio transport
 let transport = StdioTransport()
 try await server.connect(transport)

 // Server is now running and will process messages
 // To stop:
 // try await server.disconnect()
 */
