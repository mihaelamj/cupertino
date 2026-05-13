@testable import MCPClient
import MCPCore
import Testing

@Suite("MCPClient Tests")
struct MCPClientTests {
    @Test("Initialize with server command")
    func initWithCommand() async {
        let client = MCP.Client(serverCommand: "cupertino", serverArguments: ["serve"])
        let connected = await client.isConnected
        #expect(connected == false)
    }

    @Test("Initialize with full command array")
    func initWithCommandArray() async {
        let client = MCP.Client(command: ["npx", "-y", "@modelcontextprotocol/server-memory"])
        let connected = await client.isConnected
        #expect(connected == false)
    }

    @Test("Create cupertino client")
    func createCupertinoClient() async {
        let client = MCP.Client.cupertino()
        let connected = await client.isConnected
        #expect(connected == false)
    }
}
