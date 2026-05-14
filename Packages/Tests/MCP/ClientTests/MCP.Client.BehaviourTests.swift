import Foundation
@testable import MCPClient
import MCPCore
import Testing

// Behavioural coverage for `MCP.Client` and `MCP.ClientError` that does
// not depend on spawning a real subprocess. The pre-existing
// `MCPClientTests.swift` in this folder pins three init smokes; this
// file pins the rest of the disconnected-state contract: every state
// reset, every error description, and every public API that should
// fail without crashing when the client isn't connected.
//
// End-to-end coverage against a real `cupertino serve` subprocess
// belongs in an integration test target — process spawning is too slow
// and too flaky to inline here. Everything in this suite runs against
// an MCP.Client that's never had `connect()` called on it.

// MARK: - Construction state contract

@Suite("MCP.Client construction state")
struct MCPClientConstructionTests {
    @Test("serverInfo / serverCapabilities / protocolVersion are all nil before connect")
    func handshakeFieldsAreNilPreConnect() async {
        let client = MCP.Client(serverCommand: "/does/not/exist")
        let info = await client.serverInfo
        let caps = await client.serverCapabilities
        let version = await client.protocolVersion
        #expect(info == nil)
        #expect(caps == nil)
        #expect(version == nil)
    }

    @Test("Two-arg init separates executable from arguments")
    func twoArgInitStoresFields() async {
        // Construction stores the command + args but doesn't run the
        // process; isConnected stays false. We use the same field
        // shape that connect() relies on (serverCommand[0] is the
        // executable, serverArguments are the rest).
        let client = MCP.Client(serverCommand: "cupertino", serverArguments: ["serve", "--port", "9090"])
        let connected = await client.isConnected
        #expect(connected == false)
    }

    @Test("Command-array init splits head into serverCommand, tail into arguments")
    func arrayInitSplits() async {
        let client = MCP.Client(command: ["npx", "-y", "@modelcontextprotocol/server-memory"])
        let connected = await client.isConnected
        #expect(connected == false)
    }

    @Test("Empty command-array init yields a client whose connect() will fail with invalidCommand")
    func emptyArrayInitDeferredFailure() async throws {
        let client = MCP.Client(command: [])
        let connected = await client.isConnected
        #expect(connected == false)
        // connect() must throw invalidCommand on the empty-command client
        // rather than spawning anything or crashing.
        await #expect(throws: MCP.ClientError.self) {
            try await client.connect()
        }
    }

    @Test("disconnect() on a never-connected client is a safe no-op")
    func disconnectIsSafeNoOpOnIdleClient() async {
        let client = MCP.Client(serverCommand: "/does/not/exist")
        await client.disconnect()
        let connected = await client.isConnected
        #expect(connected == false)
    }
}

// MARK: - Calls fail without connect (notConnected contract)

@Suite("MCP.Client public API throws notConnected before connect()")
struct MCPClientNotConnectedTests {
    @Test("listTools() throws when not connected")
    func listToolsThrows() async {
        let client = MCP.Client(serverCommand: "/does/not/exist")
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.listTools()
        }
    }

    @Test("listResources() throws when not connected")
    func listResourcesThrows() async {
        let client = MCP.Client(serverCommand: "/does/not/exist")
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.listResources()
        }
    }

    @Test("callTool(name:) throws when not connected")
    func callToolThrows() async {
        let client = MCP.Client(serverCommand: "/does/not/exist")
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.callTool(name: "search_docs", arguments: nil)
        }
    }

    @Test("readResource(uri:) throws when not connected")
    func readResourceThrows() async {
        let client = MCP.Client(serverCommand: "/does/not/exist")
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.readResource(uri: "apple-docs://swiftui/view")
        }
    }
}

// MARK: - Cupertino convenience surface

@Suite("MCP.Client.cupertino() convenience")
struct MCPClientCupertinoConvenienceTests {
    @Test("cupertino() with explicit path returns a non-connected client")
    func explicitPathClient() async {
        let client = MCP.Client.cupertino(executablePath: "/opt/homebrew/bin/cupertino")
        let connected = await client.isConnected
        #expect(connected == false)
    }

    @Test("cupertino() without a path falls back to the default-build path")
    func defaultPathClient() async {
        // The default-search code returns the first existing path among
        // four candidates; if none exist on this machine, it falls
        // through to `.build/debug/cupertino`. Either way the client is
        // constructible and not connected.
        let client = MCP.Client.cupertino()
        let connected = await client.isConnected
        #expect(connected == false)
    }

    @Test("searchDocs / searchSamples / listSamples / readSample / readSampleFile / readDocumentation all throw notConnected when no server is running")
    func convenienceMethodsAllThrowWhenIdle() async {
        let client = MCP.Client.cupertino(executablePath: "/does/not/exist")

        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.searchDocs(query: "x")
        }
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.searchSamples(query: "x")
        }
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.listSamples()
        }
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.readSample(projectId: "noop")
        }
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.readSampleFile(projectId: "noop", filePath: "Sources/X.swift")
        }
        await #expect(throws: MCP.ClientError.self) {
            _ = try await client.readDocumentation(uri: "apple-docs://x/y")
        }
    }
}

// MARK: - ClientError contract

@Suite("MCP.ClientError descriptions")
struct MCPClientErrorTests {
    @Test("invalidCommand has a stable human-readable description")
    func invalidCommandDescription() {
        let error: MCP.ClientError = .invalidCommand
        #expect(error.errorDescription == "Invalid server command")
    }

    @Test("notConnected has a stable description")
    func notConnectedDescription() {
        let error: MCP.ClientError = .notConnected
        #expect(error.errorDescription == "Not connected to MCP server")
    }

    @Test("encodingFailed has a stable description")
    func encodingFailedDescription() {
        let error: MCP.ClientError = .encodingFailed
        #expect(error.errorDescription == "Failed to encode request")
    }

    @Test("decodingFailed has a stable description")
    func decodingFailedDescription() {
        let error: MCP.ClientError = .decodingFailed
        #expect(error.errorDescription == "Failed to decode response")
    }

    @Test("noResponse has a stable description")
    func noResponseDescription() {
        let error: MCP.ClientError = .noResponse
        #expect(error.errorDescription == "No response from server")
    }

    @Test("serverError wraps the upstream message in the description")
    func serverErrorPreservesPayload() {
        let payload = "Unsupported protocol version"
        let error: MCP.ClientError = .serverError(payload)
        #expect(error.errorDescription == "Server error: \(payload)")
    }

    @Test("ClientError is an Error and a LocalizedError")
    func clientErrorConformsToProtocols() {
        let error: any Error = MCP.ClientError.invalidCommand
        let localised = error as? LocalizedError
        #expect(localised != nil, "ClientError must conform to LocalizedError so callers get a useful errorDescription")
    }
}

// MARK: - AnyCodable wrappers used by callTool

@Suite("MCP.Core.Protocols.AnyCodable construction used by callTool arguments")
struct MCPClientAnyCodableTests {
    @Test("AnyCodable wraps a String literal")
    func wrapsString() {
        let any = MCP.Core.Protocols.AnyCodable("hello")
        #expect(any.value as? String == "hello")
    }

    @Test("AnyCodable wraps an Int literal")
    func wrapsInt() {
        let any = MCP.Core.Protocols.AnyCodable(42)
        #expect(any.value as? Int == 42)
    }

    @Test("AnyCodable wraps a Bool")
    func wrapsBool() {
        let any = MCP.Core.Protocols.AnyCodable(true)
        #expect(any.value as? Bool == true)
    }
}
