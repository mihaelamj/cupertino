import Darwin
import Foundation
import LoggingModels

// MARK: - Concurrent-save gate (#253)

//
// `cupertino save` is a one-shot heavy writer. Two simultaneous invocations
// targeting the same DB compete for the SQLite write lock, burn duplicate
// CPU/memory (per-process AST cache + per-process SwiftSourceExtractor
// passes), produce incoherent progress, and risk corrupting each other's
// WAL on shutdown.
//
// `serve` solves the analogous problem by silently reaping siblings
// (`ServeReaper`, #242). `save` cannot: every invocation is intentional
// and may already represent many hours of work; killing one without
// consent could nuke a multi-hour build.
//
// This gate detects sibling `cupertino save` processes whose target DBs
// overlap with ours, then surfaces them through an interactive prompt
// before any write. Non-interactive callers (CI, scripts) abort cleanly
// with a non-zero exit rather than silently doubling up.
//
// Scope shipped here matches the must-have set from #253:
// - sysctl KERN_PROCARGS2 argv inspection (mirrors ServeReaper)
// - path-resolved binary match (different installs coexist)
// - argv-derived target-DB enum (search / packages / samples)
// - interactive [c]/[w]/[a] prompt + non-interactive abort
//
// Deferred to a follow-up PR (mentioned in the issue):
// - `--force-replace` flag with typed-confirmation gate
// - `--from-setup` suppression for the `setup → save` pipeline

enum SaveSiblingGate {
    // MARK: - Target

    /// Which of the three local databases a `cupertino save` invocation
    /// targets. Multiple may be selected if the user passes no scope
    /// flags (the default builds all three).
    enum Target: String, CaseIterable {
        case search
        case packages
        case samples

        var dbFilename: String {
            switch self {
            case .search: return "search.db"
            case .packages: return "packages.db"
            case .samples: return "samples.db"
            }
        }
    }

    // MARK: - Sibling

    struct Sibling: Equatable {
        let pid: pid_t
        let targets: Set<Target>
        let elapsed: String
        let argv: [String]
    }

    // MARK: - Action

    enum Action: Equatable {
        case proceed
        case waitForSiblingsThenProceed(pids: [pid_t])
        case abort(reason: String)
    }

    // MARK: - Top-level gate

    /// Inspect sibling `cupertino save` processes and decide whether the
    /// current invocation may proceed. Called at the very top of
    /// `Save.run()`, before any write. Returns `.proceed` immediately
    /// when there's no sibling or no overlap; otherwise prompts (TTY)
    /// or aborts (non-TTY).
    ///
    /// `myTargets` is computed from the current invocation's parsed
    /// scope flags; `recording` is the binary's `Logging.Recording`
    /// strategy seam for output. Marked `nonisolated` so the gate can
    /// run before the actor-typed composition root is even consulted.
    static func gate(
        myTargets: Set<Target>,
        recording: any LoggingModels.Logging.Recording
    ) -> Action {
        let siblings = detectSiblings()
        let conflicting = siblings.filter { !$0.targets.intersection(myTargets).isEmpty }
        guard !conflicting.isEmpty else {
            // Sibling exists but writes a different DB → log one info
            // line and continue. Two saves writing different DBs is a
            // legitimate workflow (e.g. `save --samples` + `save --packages`
            // side by side).
            for sibling in siblings {
                let dbs = sibling.targets.map(\.dbFilename).sorted().joined(separator: ", ")
                recording.info(
                    "ℹ️  Another `cupertino save` is running (PID \(sibling.pid), \(sibling.elapsed)) building [\(dbs)] — no conflict.",
                    category: .cli
                )
            }
            return .proceed
        }

        // TTY → prompt. Non-TTY → abort.
        if isatty(fileno(stdin)) != 0 {
            return promptInteractive(conflicting: conflicting, recording: recording)
        } else {
            let overlap = conflicting
                .flatMap { $0.targets.intersection(myTargets) }
                .map(\.dbFilename)
            let unique = Set(overlap).sorted().joined(separator: ", ")
            let pids = conflicting.map { "PID \($0.pid)" }.joined(separator: ", ")
            return .abort(reason:
                "Another `cupertino save` is already building [\(unique)] (\(pids)). " +
                    "Re-run interactively to choose, or wait for it to finish.")
        }
    }

    // MARK: - Interactive prompt

    private static func promptInteractive(
        conflicting: [Sibling],
        recording: any LoggingModels.Logging.Recording
    ) -> Action {
        recording.info("", category: .cli)
        for sibling in conflicting {
            let dbs = sibling.targets.map(\.dbFilename).sorted().joined(separator: ", ")
            recording.info(
                "⚠️  Another `cupertino save` is already building [\(dbs)] — PID \(sibling.pid), started \(sibling.elapsed) ago",
                category: .cli
            )
        }
        recording.info("", category: .cli)
        recording.info("Choose:", category: .cli)
        recording.info("  [c] continue anyway (likely \"database is locked\" failures during writes)", category: .cli)
        recording.info("  [w] wait for it to finish, then start fresh", category: .cli)
        recording.info("  [a] abort", category: .cli)
        recording.info("", category: .cli)
        print("[c/w/a] ", terminator: "")

        guard let response = readLine() else {
            return .abort(reason: "No response on stdin.")
        }
        let normalized = response.trimmingCharacters(in: .whitespaces).lowercased()
        switch normalized {
        case "c", "continue":
            return .proceed
        case "w", "wait":
            return .waitForSiblingsThenProceed(pids: conflicting.map(\.pid))
        case "a", "abort", "":
            return .abort(reason: "Aborted by user.")
        default:
            return .abort(reason: "Unrecognised response '\(normalized)' — aborting.")
        }
    }

    /// Block until every supplied PID has exited (`kill(pid, 0) != 0`),
    /// printing a heartbeat through the recorder every `pollInterval`.
    /// Used by the `[w]` branch of `promptInteractive`.
    static func waitForSiblings(
        pids: [pid_t],
        pollInterval: TimeInterval = 5.0,
        recording: any LoggingModels.Logging.Recording
    ) {
        recording.info("⏳ Waiting for sibling save(s) to finish: \(pids.map(String.init).joined(separator: ", "))", category: .cli)
        var remaining = pids
        while !remaining.isEmpty {
            Thread.sleep(forTimeInterval: pollInterval)
            remaining = remaining.filter { kill($0, 0) == 0 }
            if !remaining.isEmpty {
                recording.info("⏳ Still running: \(remaining.map(String.init).joined(separator: ", "))", category: .cli)
            }
        }
        recording.info("✅ Sibling save(s) finished. Continuing.", category: .cli)
    }

    // MARK: - Argv → targets (pure, testable)

    /// Parse a `cupertino save` argv vector into the set of target DBs
    /// the invocation will build. Same defaulting rules as
    /// `Save.run()`: passing no scope flag builds all three; explicit
    /// `--docs` / `--packages` / `--samples` narrow the set.
    ///
    /// Accepts any `argv` shape: with or without the leading executable
    /// path, with or without an intervening `save` token. Detects only
    /// the first `save` token (subsequent positional args may be other
    /// values).
    ///
    /// Returns an empty set when `save` doesn't appear in argv at all.
    static func parseSaveTargets(argv: [String]) -> Set<Target> {
        guard let saveIndex = argv.firstIndex(of: "save") else { return [] }
        let rest = Array(argv[(saveIndex + 1)...])

        var hasDocs = false
        var hasPackages = false
        var hasSamples = false
        var sawScopeFlag = false
        for token in rest {
            switch token {
            case "--docs":
                hasDocs = true
                sawScopeFlag = true
            case "--packages":
                hasPackages = true
                sawScopeFlag = true
            case "--samples":
                hasSamples = true
                sawScopeFlag = true
            default:
                continue
            }
        }
        // No scope flag → all three (same default as Save.run).
        if !sawScopeFlag {
            return [.search, .packages, .samples]
        }
        var set: Set<Target> = []
        if hasDocs { set.insert(.search) }
        if hasPackages { set.insert(.packages) }
        if hasSamples { set.insert(.samples) }
        return set
    }

    // MARK: - Process snapshot

    /// Find sibling `cupertino save` processes by inspecting every
    /// running process's argv and resolved binary path. Same
    /// mechanism as `ServeReaper.reapSiblings()` but with no kill
    /// authority — purely an informational survey.
    private static func detectSiblings() -> [Sibling] {
        guard let ownPath = currentExecutablePath() else { return [] }
        let ownPID = getpid()

        var out: [Sibling] = []
        for entry in listProcesses() {
            guard entry.pid != ownPID else { continue }
            guard let argv = argvOf(pid: entry.pid),
                  argv.count >= 2,
                  argv[1] == "save"
            else { continue }
            guard let entryPath = pathOf(pid: entry.pid),
                  entryPath == ownPath
            else { continue }
            let targets = parseSaveTargets(argv: argv)
            guard !targets.isEmpty else { continue }
            out.append(Sibling(
                pid: entry.pid,
                targets: targets,
                elapsed: entry.elapsed,
                argv: argv
            ))
        }
        return out
    }

    // MARK: - System surface (duplicated from ServeReaper; #242 follow-up may consolidate)

    /// Resolved absolute path of the currently running binary.
    private static func currentExecutablePath() -> String? {
        var size: UInt32 = 4096
        var buf = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buf, &size) == 0 else { return nil }
        return resolveSymlinks(in: nullTerminatedString(from: buf))
    }

    private static func pathOf(pid: pid_t) -> String? {
        let bufLen = 4 * 1024
        var buf = [CChar](repeating: 0, count: bufLen)
        let result = proc_pidpath(pid, &buf, UInt32(bufLen))
        guard result > 0 else { return nil }
        return resolveSymlinks(in: nullTerminatedString(from: buf))
    }

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

    // MARK: - ps + procargs (mirrors ServeReaper helpers)

    struct PSEntry: Equatable {
        let pid: pid_t
        let elapsed: String
        let commandLine: String
    }

    /// Read argv via `sysctl(KERN_PROCARGS2)`. Same buffer layout as the
    /// ServeReaper helper. Returned argv may be empty if the process
    /// exited or we lack permission.
    private static func argvOf(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard mib.withUnsafeMutableBufferPointer({ ptr in
            sysctl(ptr.baseAddress, 3, nil, &size, nil, 0)
        }) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard mib.withUnsafeMutableBufferPointer({ mibPtr in
            buffer.withUnsafeMutableBufferPointer { bufPtr in
                sysctl(mibPtr.baseAddress, 3, bufPtr.baseAddress, &size, nil, 0)
            }
        }) == 0 else { return nil }

        return parseProcargs2(Array(buffer.prefix(size)))
    }

    /// xnu KERN_PROCARGS2 byte layout, same parser as
    /// `ServeReaper.parseProcargs2`. Made `internal` here so unit
    /// tests in the CLITests target can build synthetic buffers
    /// without reaching for the ServeReaper file-private copy.
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
        while offset < buffer.count && buffer[offset] != 0 {
            offset += 1
        }
        while offset < buffer.count && buffer[offset] == 0 {
            offset += 1
        }

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

    private static func listProcesses() -> [PSEntry] {
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
        let data = try? pipe.fileHandleForReading.readToEnd()
        task.waitUntilExit()
        guard let bytes = data, let output = String(data: bytes, encoding: .utf8) else {
            return []
        }
        return parsePsOutput(output)
    }

    /// Pure parser for `ps -ax -o pid=,etime=,command=` output. Exposed
    /// for unit tests.
    static func parsePsOutput(_ output: String) -> [PSEntry] {
        var entries: [PSEntry] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(
                separator: " ",
                maxSplits: 2,
                omittingEmptySubsequences: true
            )
            guard parts.count == 3, let pid = pid_t(parts[0]) else { continue }
            entries.append(PSEntry(
                pid: pid,
                elapsed: String(parts[1]),
                commandLine: String(parts[2])
            ))
        }
        return entries
    }
}
