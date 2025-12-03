@testable import MCPClient
import Testing

@Suite("MCPClient Tests")
struct MCPClientTests {
    @Test("Initialize with server command")
    func initWithCommand() async throws {
        let client = MCPClient(serverCommand: "cupertino", serverArguments: ["serve"])
        let connected = await client.isConnected
        #expect(connected == false)
    }

    @Test("Initialize with full command array")
    func initWithCommandArray() async throws {
        let client = MCPClient(command: ["npx", "-y", "@modelcontextprotocol/server-memory"])
        let connected = await client.isConnected
        #expect(connected == false)
    }

    @Test("Create cupertino client")
    func createCupertinoClient() async throws {
        let client = MCPClient.cupertino()
        let connected = await client.isConnected
        #expect(connected == false)
    }
}
