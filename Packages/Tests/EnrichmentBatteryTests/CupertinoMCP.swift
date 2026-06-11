import Foundation

/// Drives the real `cupertino serve` MCP surface for the CLI/MCP parity battery.
/// Spawns the same debug binary `CupertinoCLI` uses (so it reads the same local
/// snapshot via the co-located cupertino.config.json), performs the MCP lifecycle
/// handshake (initialize + notifications/initialized — the latter is required
/// before a spec-compliant `serve` will dispatch any further request), and
/// exposes one `callTool` that returns the concatenated text content of the
/// tool result.
///
/// One server process is spawned per call and torn down after — slower than a
/// persistent session, but it keeps each parity case hermetic and side-effect
/// free, matching how `CupertinoCLI` spawns one process per query. Spawns are
/// serialized process-wide (shared lock with the cold-DB-open contention concern
/// that `CupertinoCLI` documents).
enum CupertinoMCP {
    static var available: Bool {
        CupertinoCLI.available
    }

    struct ToolResult {
        let text: String
        let isError: Bool
    }

    private static let spawnLock = NSLock()

    /// Call one MCP tool and return its text content. `nil` only on a transport
    /// failure (no JSON-RPC response at all); a tool that legitimately returns
    /// an error frame comes back as `ToolResult(isError: true)`.
    static func callTool(_ name: String, _ arguments: [String: Any]) -> ToolResult? {
        _ = CupertinoCLI.run(["--version"]) // forces CupertinoCLI.configured (writes the config) once
        spawnLock.lock()
        defer { spawnLock.unlock() }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: CupertinoCLI.binary)
        // `--no-reap` (#280) is mandatory here: without it, each spawned serve
        // reaps its sibling `cupertino serve` processes (#242), so our own
        // back-to-back parity calls AND the neighbouring MCPIntegrationTests
        // get their servers killed mid-handshake (Transport stream closes,
        // initialize returns nil). Disabling the reaper keeps every server
        // independent.
        proc.arguments = ["serve", "--no-reap"]
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }

        func send(_ obj: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
            inPipe.fileHandleForWriting.write(data)
            inPipe.fileHandleForWriting.write(Data("\n".utf8))
        }

        send([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [:],
                "clientInfo": ["name": "parity-battery", "version": "1.0"],
            ],
        ])
        send(["jsonrpc": "2.0", "method": "notifications/initialized", "params": [:]])
        send([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
        ])
        // Closing stdin makes a spec-compliant serve drain its queue and exit,
        // so readDataToEndOfFile returns the full transcript without a deadlock.
        try? inPipe.fileHandleForWriting.close()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let transcript = String(data: data, encoding: .utf8) ?? ""

        // Find the JSON-RPC response carrying id == 2.
        for line in transcript.split(separator: "\n") {
            let lineData = Data(line.utf8)
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (obj["id"] as? Int) == 2
            else { continue }
            if obj["error"] != nil { return ToolResult(text: "", isError: true) }
            guard let result = obj["result"] as? [String: Any] else { return nil }
            let isError = (result["isError"] as? Bool) ?? false
            let blocks = (result["content"] as? [[String: Any]]) ?? []
            let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return ToolResult(text: text, isError: isError)
        }
        return nil
    }
}
