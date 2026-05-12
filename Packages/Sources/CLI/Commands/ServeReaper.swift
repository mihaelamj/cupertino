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
            // Subcommand check uses the real argv from the kernel
            // (sysctl KERN_PROCARGS2). The joined command line that ps
            // outputs is fundamentally ambiguous when paths or args
            // contain spaces or the substring 'cupertino' (--base-dir
            // /Users/me/.cupertino-dev, --search-db /tmp/cupertino.db,
            // /Applications/My Tools/cupertino, …).
            guard let argv = argvOf(pid: entry.pid),
                  argv.count >= 2,
                  argv[1] == "serve"
            else { continue }
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
        return resolveSymlinks(in: nullTerminatedString(from: buf))
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
        return resolveSymlinks(in: nullTerminatedString(from: buf))
    }

    /// Decode a null-terminated `[CChar]` buffer as a Swift String.
    /// Replaces the deprecated `String(cString:)` initializer.
    private static func nullTerminatedString(from buf: [CChar]) -> String {
        let bytes: [UInt8] = buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
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

    /// Read argv of `pid` via `sysctl(KERN_PROCARGS2)`. Returns nil if the
    /// process has exited or we lack permission to query it.
    ///
    /// Earlier revisions tried to parse the joined command line that
    /// `ps -o command=` produces, but that loses argv boundaries
    /// irrecoverably: paths with spaces, args whose values contain the
    /// substring `cupertino` (`--search-db /tmp/cupertino.db`,
    /// `--base-dir ~/.cupertino-dev`), and combinations of both all
    /// defeat any heuristic. The kernel knows the actual argv vector;
    /// asking for it directly is the only correct answer.
    private static func argvOf(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0

        // Probe for the buffer size first.
        guard mib.withUnsafeMutableBufferPointer({ ptr in
            sysctl(ptr.baseAddress, 3, nil, &size, nil, 0)
        }) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard mib.withUnsafeMutableBufferPointer({ mibPtr in
            buffer.withUnsafeMutableBufferPointer { bufPtr in
                sysctl(mibPtr.baseAddress, 3, bufPtr.baseAddress, &size, nil, 0)
            }
        }) == 0 else { return nil }

        // sysctl may have written less than the probed size; trim.
        return parseProcargs2(Array(buffer.prefix(size)))
    }

    /// Pure parser for the `KERN_PROCARGS2` byte layout. xnu format:
    ///
    ///     [argc: int32 host-endian]
    ///     [exec_path: null-terminated string]
    ///     [zero or more NUL bytes for alignment]
    ///     [argv[0]: null-terminated]
    ///     [argv[1]: null-terminated]
    ///     ...
    ///     [argv[argc-1]: null-terminated]
    ///     [envp[0]: null-terminated]   (ignored)
    ///     ...
    ///
    /// Internal so unit tests can build synthetic buffers.
    static func parseProcargs2(_ buffer: [UInt8]) -> [String]? {
        guard buffer.count >= 4 else { return nil }

        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { argcBytes in
            for i in 0..<4 {
                argcBytes[i] = buffer[i]
            }
        }
        guard argc > 0 else { return nil }

        var offset = 4

        // Skip the canonical exec_path string.
        while offset < buffer.count && buffer[offset] != 0 {
            offset += 1
        }
        // Skip the NUL terminator + any alignment padding NULs.
        while offset < buffer.count && buffer[offset] == 0 {
            offset += 1
        }

        // Read `argc` null-terminated strings starting from here.
        var argv: [String] = []
        var stringStart = offset
        while offset < buffer.count && argv.count < Int(argc) {
            if buffer[offset] == 0 {
                let bytes = Array(buffer[stringStart..<offset])
                guard let s = String(bytes: bytes, encoding: .utf8) else {
                    return nil
                }
                argv.append(s)
                stringStart = offset + 1
            }
            offset += 1
        }

        return argv.count == Int(argc) ? argv : nil
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
        } catch {
            return []
        }
        // Drain stdout BEFORE waitUntilExit. `ps -ax` on a busy machine writes
        // well over the pipe-buffer ceiling (~64 KB on macOS); if the parent
        // calls waitUntilExit() first, ps blocks on write() and the parent
        // blocks on ps exiting, deadlocking `cupertino serve` at startup.
        // readToEnd() blocks until EOF (ps closing stdout = ps exiting), then
        // waitUntilExit() returns immediately as a status confirmation.
        let data = try? pipe.fileHandleForReading.readToEnd()
        task.waitUntilExit()
        guard let bytes = data, let output = String(data: bytes, encoding: .utf8)
        else { return [] }
        return parsePsOutput(output)
    }
}
