import Darwin
import Foundation

/// Reap stale sibling `cupertino serve` processes at startup. (#242)
///
/// MCP hosts (Claude Desktop, Cursor, etc.) launch a fresh server every
/// reload of their MCP config and don't always clean up the previous one.
/// Without this reap pass, multiple servers stack up holding file
/// descriptors, SQLite read connections, and stdio handles, making
/// `cupertino save` fail more often with "database is locked" and
/// burning RAM (a few hundred MB per server once the AST cache warms).
///
/// Conservative scope by design:
/// - Only reaps processes whose absolute binary path equals our own
///   (resolved via `proc_pidpath` + `realpath`). Different installs
///   coexist (brew + dev, multiple `--base-dir` setups per #211).
/// - Only reaps processes whose first subcommand is `serve`. Concurrent
///   `cupertino save` / `fetch` survive.
/// - Skips own PID.
/// - SIGTERM, then SIGKILL after `gracePeriod` if still alive.
/// - Logs one line per reap to stderr (so it doesn't corrupt the JSON-RPC
///   stream on stdout when the host is talking to us via pipe).
enum ServeReaper {
    /// Grace period between SIGTERM and SIGKILL.
    static let gracePeriod: TimeInterval = 2.0

    static func reapSiblings() {
        guard let ownPath = currentExecutablePath() else { return }
        let ownPID = getpid()

        for entry in listProcesses() {
            guard entry.pid != ownPID else { continue }
            guard isServeSubcommand(entry.commandLine) else { continue }
            guard let entryPath = pathOf(pid: entry.pid),
                  entryPath == ownPath
            else { continue }
            reap(pid: entry.pid, elapsed: entry.elapsed)
        }
    }

    // MARK: - Reap mechanics

    private static func reap(pid: pid_t, elapsed: String) {
        guard kill(pid, SIGTERM) == 0 else { return }
        FileHandle.standardError.write(
            Data("🧹 Reaped stale serve process PID=\(pid) (running \(elapsed))\n".utf8)
        )

        let deadline = Date().addingTimeInterval(gracePeriod)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return } // gone
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Still alive after grace window — force.
        if kill(pid, 0) == 0 {
            _ = kill(pid, SIGKILL)
        }
    }

    // MARK: - Path resolution

    /// Resolved absolute path of the currently running binary.
    private static func currentExecutablePath() -> String? {
        var size: UInt32 = 4096
        var buf = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buf, &size) == 0 else { return nil }
        return resolveSymlinks(in: String(cString: buf))
    }

    /// Resolved absolute path of the binary running as `pid`, or nil if
    /// the process has exited or we lack permission to query it.
    private static func pathOf(pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is `4 * MAXPATHLEN` per
        // <sys/proc_info.h>; the macro doesn't auto-import into Swift.
        let bufLen = 4 * 1024
        var buf = [CChar](repeating: 0, count: bufLen)
        let result = proc_pidpath(pid, &buf, UInt32(bufLen))
        guard result > 0 else { return nil }
        return resolveSymlinks(in: String(cString: buf))
    }

    private static func resolveSymlinks(in path: String) -> String {
        path.withCString { cpath in
            guard let resolved = realpath(cpath, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    // MARK: - ps parsing (testable surface)

    struct Entry: Equatable {
        let pid: pid_t
        let elapsed: String
        let commandLine: String
    }

    /// Detects whether a command line's first subcommand (token after the
    /// binary path) is `serve`. Word-boundary check, so a command like
    /// `cupertino server-something` would NOT match (defensive against
    /// future subcommands containing the substring "serve").
    static func isServeSubcommand(_ commandLine: String) -> Bool {
        // Skip past the binary token. Use Substring slicing rather than
        // .split() so we don't lose argv-with-spaces edge cases.
        let trimmed = commandLine.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(of: " ") else {
            return false // no subcommand at all
        }
        let afterBinary = trimmed[trimmed.index(after: firstSpace)...]
            .trimmingCharacters(in: .whitespaces)
        // First token after binary must be exactly `serve`.
        let firstToken = afterBinary.split(separator: " ", maxSplits: 1).first ?? ""
        return firstToken == "serve"
    }

    /// Parses `ps -ax -o pid=,etime=,command=` output into Entry records.
    /// Public for unit testability; not part of the runtime API.
    static func parsePsOutput(_ output: String) -> [Entry] {
        var entries: [Entry] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(
                separator: " ",
                maxSplits: 2,
                omittingEmptySubsequences: true
            )
            guard parts.count == 3,
                  let pid = pid_t(parts[0])
            else { continue }
            entries.append(Entry(
                pid: pid,
                elapsed: String(parts[1]),
                commandLine: String(parts[2])
            ))
        }
        return entries
    }

    private static func listProcesses() -> [Entry] {
        let task = Foundation.Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid=,etime=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8)
        else { return [] }
        return parsePsOutput(output)
    }
}
