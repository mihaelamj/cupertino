import Testing
@testable import MCPServer

@Test func testServerInitialization() async throws {
    let server = await MCPServer(name: "test", version: "1.0.0")
    // Placeholder test
    #expect(true)
}
