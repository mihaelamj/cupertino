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
// #722 follow-up shipped on top of the must-have:
// - `--force-replace` flag with typed-confirmation gate + SIGTERM /
//   grace / SIGKILL termination ladder for the sibling save
// - `--yes` non-interactive bypass for the typed-confirmation prompt
//   (CI / scripted invocations)
//
// Out of scope (the `--from-setup` half from #722's issue body was
// found moot — `cupertino setup` is a download-and-extract pipeline,
// not a setup→save subprocess pipeline; no spawned-save false-positive
// exists today).

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
        /// #722 — `--force-replace` authorised by the user. Caller is
        /// expected to invoke `terminateSiblings(pids:recording:)`
        /// before proceeding with the save.
        case forceReplaceSiblings(pids: [pid_t])
    }

    /// Outcome of `parseTypedReplaceConfirmation(_:)`. Lifted out so
    /// tests can assert on the discrete branches without depending on
    /// the I/O wrapper that reads stdin.
    enum TypedConfirmation: Equatable {
        case accepted
        case rejected(input: String)
    }

    /// Outcome of `terminateSiblings(...)`. Surfaces whether every
    /// requested PID actually died so callers can refuse to proceed
    /// (and hit `database is locked`) when SIGKILL didn't take.
    ///
    /// `.allTerminated` — every PID passed `kill(pid, 0) != 0` after
    /// the SIGKILL fallback. Safe to proceed.
    ///
    /// `.stragglers(pids:)` — one or more PIDs are still responding
    /// to `kill(pid, 0)` after the grace window + SIGKILL. Either
    /// uninterruptible-sleep (D-state), zombie not yet reaped, or
    /// we hit EPERM. Caller MUST NOT proceed — they'd land on the
    /// same lock the sibling holds.
    enum TerminationOutcome: Equatable {
        case allTerminated
        case stragglers(pids: [pid_t])
    }

    /// Errors `Save.run()` surfaces from the gate (#722 follow-up).
    enum GateError: Error, Equatable {
        /// `terminateSiblings(...)` returned `.stragglers`. Caller
        /// aborts cleanly with a clear reason rather than cascading
        /// into a SQLite `database is locked` failure.
        case terminationFailed(stragglers: [pid_t])
    }

    /// Parse the typed-confirmation gate's stdin response (#722). The
    /// gate requires the literal word `replace` (case-insensitive,
    /// surrounding whitespace tolerated) — anything else aborts.
    ///
    /// Pure function so the test surface doesn't need to drive stdin.
    /// The interactive prompt at the call site reads the response with
    /// `readLine()` and forwards into this parser.
    static func parseTypedReplaceConfirmation(_ raw: String?) -> TypedConfirmation {
        guard let raw else { return .rejected(input: "") }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "replace" ? .accepted : .rejected(input: raw)
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
        recording: any LoggingModels.Logging.Recording,
        forceReplace: Bool = false,
        assumeYes: Bool = false,
        isInteractive: () -> Bool = { isatty(fileno(stdin)) != 0 },
        readConfirmation: () -> String? = { readLine() },
        siblingDetector: () -> [Sibling] = Self.detectSiblings
    ) -> Action {
        let siblings = siblingDetector()
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

        // #722 — `--force-replace` short-circuits the [c]/[w]/[a]
        // prompt. The user has explicitly opted into killing the
        // sibling save. Still gated by a typed-confirmation step
        // (interactive TTY) or `--yes` (CI / scripted) — never
        // unconditional, because nuking a multi-hour build by
        // accident is exactly the class-of-bug this PR exists to
        // prevent.
        if forceReplace {
            return promptForceReplace(
                conflicting: conflicting,
                assumeYes: assumeYes,
                recording: recording,
                isInteractive: isInteractive,
                readConfirmation: readConfirmation
            )
        }

        // TTY → prompt. Non-TTY → abort.
        if isInteractive() {
            return promptInteractive(
                conflicting: conflicting,
                recording: recording,
                readConfirmation: readConfirmation
            )
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

    // MARK: - Force-replace path (#722)

    /// Handle the `--force-replace` opt-in. Two sub-paths:
    ///
    /// 1. Interactive TTY + no `--yes` → typed-confirmation gate.
    ///    User must type the literal word `replace` to authorise
    ///    SIGTERM. Single keystroke isn't enough — this is the kind
    ///    of action that should never happen by mistake.
    /// 2. `--yes` set (or non-TTY with `--yes`) → log the action +
    ///    return `.forceReplaceSiblings` immediately. Skips the
    ///    typed-confirmation gate because the caller already opted
    ///    in via flag.
    ///
    /// Non-TTY without `--yes` → abort, same as the unscripted-non-
    /// interactive case. `--force-replace` alone is meaningless in
    /// a non-interactive context.
    private static func promptForceReplace(
        conflicting: [Sibling],
        assumeYes: Bool,
        recording: any LoggingModels.Logging.Recording,
        isInteractive: () -> Bool,
        readConfirmation: () -> String?
    ) -> Action {
        let pids = conflicting.map(\.pid)
        let pidsString = pids.map(String.init).joined(separator: ", ")

        // `--yes` short-circuits the typed gate.
        if assumeYes {
            recording.info("", category: .cli)
            for sibling in conflicting {
                let dbs = sibling.targets.map(\.dbFilename).sorted().joined(separator: ", ")
                recording.info(
                    "⚠️  --force-replace --yes: will SIGTERM PID \(sibling.pid) (cupertino save, \(sibling.elapsed) elapsed, building [\(dbs)])",
                    category: .cli
                )
            }
            return .forceReplaceSiblings(pids: pids)
        }

        // Non-TTY without `--yes` → abort. `--force-replace` needs
        // either an interactive confirmation or an explicit `--yes`;
        // unattended force-kill is exactly the foot-gun this gate
        // exists to prevent.
        guard isInteractive() else {
            return .abort(reason:
                "--force-replace requires either an interactive TTY (for the typed-confirmation gate) " +
                    "or `--yes` to bypass. Non-interactive invocation refused — re-run with `--yes` " +
                    "to authorise SIGTERM on PID(s) \(pidsString).")
        }

        // Typed-confirmation gate.
        recording.info("", category: .cli)
        recording.info("⚠️  --force-replace will SIGTERM the following sibling save(s):", category: .cli)
        for sibling in conflicting {
            let dbs = sibling.targets.map(\.dbFilename).sorted().joined(separator: ", ")
            recording.info(
                "   PID \(sibling.pid)  •  \(sibling.elapsed) elapsed  •  building [\(dbs)]",
                category: .cli
            )
        }
        recording.info("", category: .cli)
        recording.info("This will lose any in-flight work the sibling has done.", category: .cli)
        recording.info("Type 'replace' to confirm:", category: .cli)
        print("> ", terminator: "")

        switch parseTypedReplaceConfirmation(readConfirmation()) {
        case .accepted:
            recording.info("✅ confirmed — SIGTERMing PID(s) \(pidsString)", category: .cli)
            return .forceReplaceSiblings(pids: pids)
        case .rejected(let input):
            let echoed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            return .abort(reason:
                "Typed-confirmation gate rejected input '\(echoed)' (expected 'replace'). " +
                    "No siblings were terminated.")
        }
    }

    /// SIGTERM each sibling PID, wait up to `graceSeconds` for clean
    /// exit (so SQLite has time to flush its WAL + checkpoint), then
    /// SIGKILL any that didn't exit. Caller is expected to have already
    /// passed the typed-confirmation gate (`promptForceReplace`).
    ///
    /// Defensive against three real failure modes:
    ///
    /// 1. **PID reuse race.** Between `detectSiblings()` and our
    ///    `kill(SIGTERM)`, the sibling could have exited naturally and
    ///    macOS could have reused the PID for an unrelated process.
    ///    Each PID is re-verified via `verifier(pid)` (default:
    ///    `verifyStillSibling`) before SIGTERM — checks argv[1] == "save"
    ///    + same resolved binary path. PIDs that fail re-verification
    ///    are dropped from the kill set and logged.
    /// 2. **SIGKILL didn't take.** EPERM (cross-user), D-state
    ///    (uninterruptible sleep), or any other reason a kill might
    ///    silently fail. After the SIGKILL fallback we do one final
    ///    `kill(pid, 0)` per PID and surface the survivors as
    ///    `.stragglers(pids:)` so the caller can refuse to proceed
    ///    rather than cascading into a `database is locked` failure.
    /// 3. **Grace window too short.** A near-completed save mid-
    ///    checkpoint may need >30s. `graceSeconds` is configurable
    ///    (CLI flag `--force-replace-grace`); the default is a
    ///    practical floor, not a hard cap.
    ///
    /// Grace ladder rationale: SIGKILL mid-INSERT leaves the DB in a
    /// `database is locked` / `database disk image is malformed`
    /// state — exactly the corruption class this gate exists to
    /// prevent. SIGTERM-then-wait is the safe path; SIGKILL is the
    /// last resort for stuck processes.
    @discardableResult
    static func terminateSiblings(
        pids: [pid_t],
        graceSeconds: TimeInterval = 30,
        pollInterval: TimeInterval = 1.0,
        recording: any LoggingModels.Logging.Recording,
        verifier: (pid_t) -> Bool = Self.verifyStillSibling
    ) -> TerminationOutcome {
        guard !pids.isEmpty else { return .allTerminated }

        // #722 Bug-1 mitigation — re-verify each PID still resolves to
        // a cupertino-save sibling before SIGTERM. Closes the
        // detect→kill TOCTOU window from seconds to a single syscall.
        let verifiedPIDs = pids.filter { pid in
            if verifier(pid) { return true }
            recording.info(
                "ℹ️  PID \(pid) is no longer a cupertino save sibling — dropped from force-replace set (likely natural exit + PID reuse).",
                category: .cli
            )
            return false
        }
        guard !verifiedPIDs.isEmpty else {
            // Pass-2 review note: this is `.allTerminated` because we
            // sent no signal AND we can't safely assume the PIDs are
            // alive (kill(pid, 0) before SIGTERM would be the same
            // race the verifier just closed). The honest log is "no
            // verified target": if a sibling save was actually still
            // running but verifier failed transiently (e.g. sysctl
            // hiccup), `Save.run()` will land on the existing SQLite
            // lock failure — same downstream as pre-#722, no
            // regression.
            recording.info(
                "ℹ️  No verified siblings left to terminate (re-verification dropped every PID; siblings likely already exited).",
                category: .cli
            )
            return .allTerminated
        }

        recording.info("⚠️  Sending SIGTERM to PID(s) \(verifiedPIDs.map(String.init).joined(separator: ", "))", category: .cli)
        for pid in verifiedPIDs {
            if kill(pid, SIGTERM) != 0, errno != ESRCH {
                recording.warning("⚠️  SIGTERM PID \(pid) failed (errno \(errno)); will SIGKILL after grace.", category: .cli)
            }
        }

        // Wait up to `graceSeconds`, polling each `pollInterval`. Any
        // PID still alive after grace gets SIGKILL.
        let deadline = Date().addingTimeInterval(graceSeconds)
        var remaining = Set(verifiedPIDs)
        while !remaining.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            remaining = remaining.filter { kill($0, 0) == 0 }
            if !remaining.isEmpty {
                recording.info(
                    "⏳ waiting for clean exit: PID(s) \(remaining.map(String.init).sorted().joined(separator: ", "))",
                    category: .cli
                )
            }
        }
        // SIGKILL stragglers.
        for pid in remaining {
            recording.warning("⚠️  PID \(pid) didn't exit within \(Int(graceSeconds))s — SIGKILL.", category: .cli)
            _ = kill(pid, SIGKILL)
        }

        // #722 Bug-2 mitigation — verify SIGKILL actually took. EPERM,
        // D-state, or zombie-not-yet-reaped can leave the PID alive
        // even after SIGKILL. One small settle window (SIGKILL is
        // async on macOS) then one final probe before declaring
        // success. Survivors are surfaced to the caller so it can
        // abort rather than cascade into `database is locked`.
        Thread.sleep(forTimeInterval: pollInterval)
        let survivors = remaining.filter { kill($0, 0) == 0 }.sorted()
        if survivors.isEmpty {
            recording.info("✅ Sibling save(s) terminated. Continuing.", category: .cli)
            return .allTerminated
        } else {
            recording.error(
                "❌ Termination incomplete — PID(s) \(survivors.map(String.init).joined(separator: ", ")) still alive after SIGKILL. " +
                    "Likely cross-user EPERM or stuck in uninterruptible sleep. Aborting before opening the DB.",
                category: .cli
            )
            return .stragglers(pids: survivors)
        }
    }

    /// Re-verify a PID still represents a cupertino-save sibling
    /// (#722 Bug-1 mitigation against PID reuse race). Mirrors the
    /// checks `detectSiblings()` does — argv[1] == "save" + same
    /// resolved binary path. Returns `true` only when both hold;
    /// `false` for any failure mode (dead PID, wrong process, can't
    /// read argv, can't resolve path).
    static func verifyStillSibling(_ pid: pid_t) -> Bool {
        guard let ownPath = currentExecutablePath() else { return false }
        guard let argv = argvOf(pid: pid),
              argv.count >= 2,
              argv[1] == "save"
        else { return false }
        guard let entryPath = pathOf(pid: pid),
              entryPath == ownPath
        else { return false }
        return true
    }

    // MARK: - Interactive prompt

    private static func promptInteractive(
        conflicting: [Sibling],
        recording: any LoggingModels.Logging.Recording,
        readConfirmation: () -> String? = { readLine() }
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

        guard let response = readConfirmation() else {
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
