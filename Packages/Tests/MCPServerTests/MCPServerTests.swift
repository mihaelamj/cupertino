@testable import MCPServer
import Testing

@Test func serverInitialization() async throws {
    _ = MCPServer(name: "test", version: "1.0.0")
    // Test passes if we can create a server without crashing
    #expect(Bool(true))
}
