import Foundation
import SharedConstants
import SwiftMCPClient
import SwiftMCPClientAPI
import SwiftMCPSubprocessTransport
import SwiftMCPTransport

// MARK: - Mock AI Agent

// A mock AI agent that demonstrates a full MCP request/response cycle against
// `cupertino serve` (or any external MCP server).
//
// #1172: this used to hand-roll its own stdio `MCPClient` actor (process
// management + JSON-RPC framing + request/response correlation). It now drives
// the neutral, transport-injectable `SwiftMCPClient` over a
// `Transport.Subprocess` channel: the client owns the `initialize` handshake
// (including the `notifications/initialized` lifecycle notification a
// spec-compliant `cupertino serve` requires before it answers anything), the
// subprocess lifecycle, framing, and request correlation. The agent is reduced
// to the demo script + presentation. Adopting the `Client.MCP` seam means the
// demo prints the server's extracted payloads (tool list, server info, search
// + resource text) rather than raw wire JSON; the wire detail lives inside the
// shared client now.

@main
struct MockAIAgent {
    static func main() async throws {
        // Force flush output immediately
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        let rawArgs = CommandLine.arguments

        // Handle --version flag
        if rawArgs.contains("--version") || rawArgs.contains("-v") {
            print(Shared.Constants.App.version)
            return
        }

        // Parse --quiet (presentation/demo mode): suppress the verbose
        // per-payload dumps, keeping the high-level "SERVER → CLIENT" summary
        // lines so the demo still tells a story.
        let quiet = rawArgs.contains("--quiet") || rawArgs.contains("-q")

        // Parse --response-timeout <seconds>. Default 30s preserved for
        // back-compat; CI smoke runs that hit a cold-start MCP server pass
        // `--response-timeout 60` to absorb the worst observed cold start.
        // See memory: cupertino-mcp-cold-start-ci-timeout.md.
        var responseTimeoutSeconds = 30
        if let flagIdx = rawArgs.firstIndex(of: "--response-timeout"),
           flagIdx + 1 < rawArgs.count,
           let parsed = Int(rawArgs[flagIdx + 1]),
           parsed > 0 {
            responseTimeoutSeconds = parsed
        }

        let args = rawArgs.enumerated().filter { idx, value in
            if value == "--quiet" || value == "-q" { return false }
            if value == "--response-timeout" { return false }
            // Drop the value paired with --response-timeout (idx-1 holds the flag).
            if idx > 0, rawArgs[idx - 1] == "--response-timeout" { return false }
            return true
        }.map(\.element)

        print("🤖 Mock AI Agent Starting...")
        print("=".repeating(80))
        print()

        // Resolve the server command. External-server mode:
        //   mock-ai-agent npx -y @modelcontextprotocol/server-memory
        let command: String
        let arguments: [String]
        if args.count > 1 {
            let cmd = Array(args.dropFirst())
            command = cmd[0]
            arguments = Array(cmd.dropFirst())
            print("📡 Using external MCP server:")
            print("   Command: \(cmd.joined(separator: " "))")
            print()
        } else {
            command = findCupertinoExecutable()
            arguments = ["serve"]
            print("📡 Using cupertino server: \(command) \(arguments.joined(separator: " "))")
            print()
        }

        let demo = Demo(quiet: quiet)
        do {
            let transport = Transport.Subprocess(command: command, arguments: arguments)
            let client = MCPClient(
                transport: transport,
                clientName: "Mock AI Agent",
                clientVersion: "1.0.0",
                requestTimeout: .seconds(responseTimeoutSeconds)
            )
            try await demo.run(client: client)
        } catch {
            print("❌ Error: \(error)")
            throw error
        }
    }

    /// Resolve the local cupertino binary as an ABSOLUTE path. Only the local
    /// build is used (never an installed version), so the agent always exercises
    /// the current code. `Transport.Subprocess` runs a non-`/` command through
    /// `/usr/bin/env` (a PATH lookup), which would not find a relative build
    /// path, hence the absolutisation.
    private static func findCupertinoExecutable() -> String {
        let cwd = FileManager.default.currentDirectoryPath
        let buildLocations = [
            "\(cwd)/.build/debug/cupertino",
            "\(cwd)/.build/release/cupertino",
        ]
        for location in buildLocations where FileManager.default.fileExists(atPath: location) {
            return location
        }
        print("❌ ERROR: No local build found!")
        print("   MockAIAgent requires a local build to test current code.")
        print("   Run: swift build")
        print("   Then: swift run mock-ai-agent")
        print()
        print("   (Not using an installed cupertino to avoid testing the wrong binary)")
        fatalError("Build cupertino first: swift build")
    }
}

// MARK: - Demo

/// The presentation script. Owns no protocol machinery: it drives the injected
/// `Client.MCP` seam and renders what the server returns.
private struct Demo {
    let quiet: Bool

    func run(client: some Client.MCP) async throws {
        print("📡 Starting MCP Communication...")
        print("=".repeating(80))
        print()

        // `connect()` starts the transport (spawns the process + wires pipes for
        // the subprocess channel), performs the `initialize` handshake, AND sends
        // the `notifications/initialized` lifecycle notification a spec-compliant
        // `cupertino serve` requires before it dispatches any further request.
        print("📨 CLIENT → SERVER: connect (initialize + notifications/initialized)")
        print("-".repeating(80))
        try await client.connect()
        print("✅ Connected")

        if let info = await client.serverInfo() {
            print("   Server: \(info.name) v\(info.version)")
            print("   Protocol Version: \(info.protocolVersion)")
            if let instructions = info.instructions, !instructions.isEmpty {
                print("   Instructions: \(instructions)")
            }
            if !quiet {
                print("   Capabilities: \(info.capabilitiesJSON)")
            }
        }
        print()

        try await listTools(client: client)
        try await callSearch(client: client, query: "SwiftUI")
        let resources = try await listResources(client: client)
        try await readRandomResource(client: client, from: resources)

        print("📨 CLIENT → SERVER: disconnect")
        print("-".repeating(80))
        await client.disconnect()
        print("✅ Disconnected")

        print()
        print("=".repeating(80))
        print("✅ Mock AI Agent Complete")
    }

    private func listTools(client: some Client.MCP) async throws {
        print("📨 CLIENT → SERVER: tools/list")
        print("-".repeating(80))
        let tools = try await client.listTools()
        print("✅ Found \(tools.count) tools:")
        for tool in tools {
            print("   - \(tool.name): \(tool.description ?? "(no description)")")
            if !quiet {
                print("     Input schema: \(tool.inputSchemaJSON)")
            }
        }
        print()
    }

    private func callSearch(client: some Client.MCP, query: String) async throws {
        let toolName = Shared.Constants.Search.toolSearch
        print("📨 CLIENT → SERVER: tools/call (\(toolName))")
        print("-".repeating(80))
        print("   Query: \"\(query)\"")
        print()
        let result = try await client.callTool(
            toolName,
            arguments: [
                "query": .string(query),
                "limit": .int(5),
            ]
        )
        print("📬 SERVER → CLIENT: tools/call result")
        print("-".repeating(80))
        let preview = String(result.prefix(quiet ? 200 : 1000))
        print(preview + (result.count > preview.count ? "..." : ""))
        print()
    }

    private func listResources(client: some Client.MCP) async throws -> [Client.ResourceInfo] {
        print("📨 CLIENT → SERVER: resources/list")
        print("-".repeating(80))
        let resources = try await client.listResources()
        print("✅ Found \(resources.count) resources:")
        for resource in resources.prefix(quiet ? 5 : resources.count) {
            print("   - \(resource.uri): \(resource.name)")
            if !quiet, let mimeType = resource.mimeType {
                print("     MIME: \(mimeType)")
            }
        }
        print()
        return resources
    }

    private func readRandomResource(client: some Client.MCP, from resources: [Client.ResourceInfo]) async throws {
        // Pick a real URI from whatever the server returned, rather than a
        // hardcoded constant that drifts when the bundle re-publishes (#583).
        guard let chosen = resources.randomElement() else {
            print("⚠️  resources/list returned zero entries — skipping resources/read.")
            print()
            return
        }
        print("🎲 Randomly chose for resources/read: \(chosen.uri)")
        print("📨 CLIENT → SERVER: resources/read")
        print("-".repeating(80))
        print("   URI: \(chosen.uri)")
        print()
        let text = try await client.readResource(chosen.uri)
        print("📬 SERVER → CLIENT: resources/read result")
        print("-".repeating(80))
        let preview = String(text.prefix(quiet ? 200 : 1000))
        print(preview + (text.count > preview.count ? "..." : ""))
        print()
    }
}

// MARK: - Extensions

extension String {
    func repeating(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
