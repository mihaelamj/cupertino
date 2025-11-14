import Testing
@testable import MCPServer

@Test func testServerInitialization() async throws {
    _ = MCPServer(name: "test", version: "1.0.0")
    // Test passes if we can create a server without crashing
    #expect(Bool(true))
}
