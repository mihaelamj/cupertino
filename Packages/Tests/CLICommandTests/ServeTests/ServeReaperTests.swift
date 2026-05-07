@testable import CLI
import Foundation
import Testing

// Unit coverage for the testable surface of `ServeReaper` (#242).
// The runtime reap loop (kill / proc_pidpath / spawning ps / sysctl)
// is exercised only by manual / staging verification — this suite
// covers the pure parsing layers that decide which processes get
// reaped:
//
//   - `parsePsOutput` (PID + elapsed-time extraction from ps output)
//   - `parseProcargs2` (argv extraction from the kernel-format byte
//     buffer that `sysctl(KERN_PROCARGS2)` returns)
//
// Earlier revisions tried to detect the `serve` subcommand by parsing
// the joined command line that `ps -o command=` outputs. That layer
// got patched twice and still missed real-world failures because the
// joined string loses argv boundaries irrecoverably. The kernel knows
// the truth; we now ask it.

@Suite("ServeReaper parsing")
struct ServeReaperTests {
    // MARK: - parsePsOutput

    @Test("parses a typical ps -ax -o pid=,etime=,command= line")
    func parsesTypicalLine() throws {
        let output = "12345     1-02:30:45 /usr/local/bin/cupertino serve\n"
        let entries = ServeReaper.parsePsOutput(output)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.pid == 12345)
        #expect(entry.elapsed == "1-02:30:45")
        #expect(entry.commandLine == "/usr/local/bin/cupertino serve")
    }

    @Test("preserves command-line arguments after the binary path")
    func preservesArgs() throws {
        let output = "98765   00:30 /opt/homebrew/bin/cupertino serve --search-db /tmp/x\n"
        let entry = try #require(ServeReaper.parsePsOutput(output).first)
        #expect(entry.commandLine == "/opt/homebrew/bin/cupertino serve --search-db /tmp/x")
    }

    @Test("handles multiple lines and skips blank lines")
    func multipleLines() {
        let output = """
            12345 00:30 /usr/local/bin/cupertino serve

            54321 1:20 /usr/local/bin/cupertino save

            99999 02:00 /bin/bash -c whatever
            """
        let entries = ServeReaper.parsePsOutput(output)
        #expect(entries.count == 3)
        #expect(entries.map(\.pid) == [12345, 54321, 99999])
    }

    @Test("skips lines without a parseable pid")
    func skipsMalformed() throws {
        let output = """
            not-a-pid 00:30 /usr/local/bin/cupertino serve
            12345 00:10 /usr/local/bin/cupertino serve
            """
        let entries = ServeReaper.parsePsOutput(output)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.pid == 12345)
    }

    @Test("skips lines with too few fields")
    func skipsShortLines() {
        let output = "12345\n12345 00:10\n"
        let entries = ServeReaper.parsePsOutput(output)
        #expect(entries.isEmpty)
    }

    // MARK: - parseProcargs2 (kernel argv buffer)

    @Test("parses a typical KERN_PROCARGS2 buffer")
    func parsesTypicalProcargs2() {
        let buf = buildProcargs2(
            execPath: "/usr/local/bin/cupertino",
            argv: ["/usr/local/bin/cupertino", "serve"]
        )
        #expect(ServeReaper.parseProcargs2(buf) == [
            "/usr/local/bin/cupertino",
            "serve",
        ])
    }

    @Test("preserves argument values containing 'cupertino' (regression for codex review on #267)")
    func argValuesContainCupertino() {
        // The realistic case codex flagged: --search-db /tmp/cupertino.db
        // The previous string-anchored matcher resolved to `.db` and missed
        // the process. Argv-based parsing returns the actual vector so
        // argv[1] is unambiguously `serve` regardless of what later args
        // contain.
        let cases: [[String]] = [
            ["/usr/local/bin/cupertino", "serve", "--search-db", "/tmp/cupertino.db"],
            ["/usr/local/bin/cupertino", "serve", "--base-dir", "/Users/me/.cupertino-dev"],
            [
                "/Applications/My Tools/cupertino", "serve",
                "--search-db", "/tmp/cupertino-search.db",
            ],
        ]
        for argv in cases {
            let buf = buildProcargs2(execPath: argv[0], argv: argv)
            #expect(ServeReaper.parseProcargs2(buf) == argv)
        }
    }

    @Test("handles binary paths that contain spaces (regression for first codex review on #267)")
    func binaryPathWithSpaces() {
        let buf = buildProcargs2(
            execPath: "/Applications/My Tools/cupertino",
            argv: ["/Applications/My Tools/cupertino", "serve"]
        )
        let argv = ServeReaper.parseProcargs2(buf)
        #expect(argv == ["/Applications/My Tools/cupertino", "serve"])
    }

    @Test("handles arbitrary alignment padding between exec_path and argv[0]")
    func alignmentPadding() {
        // xnu pads exec_path's NUL terminator out to an alignment boundary.
        // We don't know the exact alignment ahead of time; the parser
        // should tolerate any number of trailing NULs before argv[0].
        for padding in [0, 1, 3, 7, 15] {
            let buf = buildProcargs2(
                execPath: "/usr/local/bin/cupertino",
                argv: ["cupertino", "serve"],
                padding: padding
            )
            let argv = ServeReaper.parseProcargs2(buf)
            #expect(argv == ["cupertino", "serve"], "padding=\(padding)")
        }
    }

    @Test("ignores envp following argv (does not read past argc strings)")
    func ignoresEnvironment() {
        let buf = buildProcargs2(
            execPath: "/usr/local/bin/cupertino",
            argv: ["cupertino", "serve"],
            envp: ["HOME=/Users/me", "PATH=/usr/bin:/bin"]
        )
        let argv = ServeReaper.parseProcargs2(buf)
        #expect(argv == ["cupertino", "serve"])
    }

    @Test("rejects buffers that are too short")
    func rejectsTooShort() {
        #expect(ServeReaper.parseProcargs2([]) == nil)
        #expect(ServeReaper.parseProcargs2([0, 0, 0]) == nil)
    }

    @Test("rejects argc=0 buffers (no argv to inspect)")
    func rejectsZeroArgc() {
        let buf: [UInt8] = [0, 0, 0, 0] + Array("/usr/local/bin/cupertino\0".utf8)
        #expect(ServeReaper.parseProcargs2(buf) == nil)
    }

    @Test("returns nil when buffer truncates mid-argv")
    func truncatedBuffer() {
        // Build a buffer claiming argc=3 but supplying only 2 strings.
        var buf: [UInt8] = []
        var argc = Int32(3)
        withUnsafeBytes(of: &argc) { buf.append(contentsOf: $0) }
        buf.append(contentsOf: "/usr/local/bin/cupertino\0".utf8)
        buf.append(contentsOf: "cupertino\0".utf8)
        buf.append(contentsOf: "serve\0".utf8)
        // Only 2 strings provided; parser should return nil.
        #expect(ServeReaper.parseProcargs2(buf) == nil)
    }
}

// MARK: - Test fixture helpers

/// Builds a synthetic `KERN_PROCARGS2` byte buffer in the xnu format the
/// real `sysctl` returns. Layout per xnu `bsd/kern/kern_sysctl.c`:
///
///     [argc: int32 host-endian]
///     [exec_path: null-terminated]
///     [`padding` extra NUL bytes for alignment]
///     [argv[0]: null-terminated]
///     ...
///     [argv[argc-1]: null-terminated]
///     [envp[0]: null-terminated]
///     ...
private func buildProcargs2(
    execPath: String,
    argv: [String],
    padding: Int = 0,
    envp: [String] = []
) -> [UInt8] {
    var buffer: [UInt8] = []
    var argc = Int32(argv.count)

    withUnsafeBytes(of: &argc) { bytes in
        buffer.append(contentsOf: bytes)
    }

    buffer.append(contentsOf: execPath.utf8)
    buffer.append(0)
    for _ in 0..<padding {
        buffer.append(0)
    }

    for arg in argv {
        buffer.append(contentsOf: arg.utf8)
        buffer.append(0)
    }

    for env in envp {
        buffer.append(contentsOf: env.utf8)
        buffer.append(0)
    }

    return buffer
}
