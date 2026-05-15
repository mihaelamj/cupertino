@testable import CLI
import Darwin
import Foundation
import LoggingModels
import Testing

// Covers `SaveSiblingGate` (#253). The detection / waitForSiblings
// runtime paths spawn `/bin/ps` and read foreign-process state, so this
// suite focuses on the pure parts: argv → target-set parsing, ps-output
// parsing, procargs2 buffer parsing, and the bad-cursor recovery shape
// in the cursor codec by analogy. Integration (gate against a real
// sibling save) is left to a manual reproduction script.

// MARK: - Argv → Target parsing

@Suite("SaveSiblingGate.parseSaveTargets")
struct ParseSaveTargetsTests {
    @Test("Empty argv → empty set")
    func emptyArgv() {
        #expect(SaveSiblingGate.parseSaveTargets(argv: []).isEmpty)
    }

    @Test("argv without 'save' token → empty set")
    func noSaveToken() {
        let argv = ["/usr/local/bin/cupertino", "serve"]
        #expect(SaveSiblingGate.parseSaveTargets(argv: argv).isEmpty)
    }

    @Test("'save' with no scope flag → all three targets")
    func defaultBuildsAllThree() {
        let argv = ["/usr/local/bin/cupertino", "save"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .packages, .samples])
    }

    @Test("--docs only → search.db only")
    func docsOnly() {
        let argv = ["/usr/local/bin/cupertino", "save", "--docs"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search])
    }

    @Test("--packages only → packages.db only")
    func packagesOnly() {
        let argv = ["cupertino", "save", "--packages"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.packages])
    }

    @Test("--samples only → samples.db only")
    func samplesOnly() {
        let argv = ["cupertino", "save", "--samples"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.samples])
    }

    @Test("--docs + --samples → search + samples (packages excluded)")
    func docsAndSamples() {
        let argv = ["cupertino", "save", "--docs", "--samples"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .samples])
    }

    @Test("--docs --packages --samples → all three explicitly")
    func allThreeExplicit() {
        let argv = ["cupertino", "save", "--docs", "--packages", "--samples"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .packages, .samples])
    }

    @Test("Unrelated flags between scope flags are ignored")
    func ignoresUnrelatedFlags() {
        let argv = ["cupertino", "save", "--docs", "--yes", "--base-dir", "/tmp/c", "--samples"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .samples])
    }

    @Test("'save' appearing after a leading non-binary token still parses")
    func saveNotAtArgvZero() {
        // E.g. when the binary was invoked through a wrapper script that
        // forwards argv after its own first arg.
        let argv = ["wrapper", "cupertino", "save", "--packages"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.packages])
    }

    @Test("Target.dbFilename matches the canonical names")
    func dbFilenames() {
        #expect(SaveSiblingGate.Target.search.dbFilename == "search.db")
        #expect(SaveSiblingGate.Target.packages.dbFilename == "packages.db")
        #expect(SaveSiblingGate.Target.samples.dbFilename == "samples.db")
    }
}

// MARK: - ps output parser

@Suite("SaveSiblingGate.parsePsOutput")
struct ParsePsOutputTests {
    @Test("Three-column line parses pid + elapsed + command")
    func threeColumns() {
        let output = """
        57122 06:39:12 /usr/local/bin/cupertino save --docs
        90624 00:01:23 /opt/homebrew/bin/cupertino save --packages
        """
        let entries = SaveSiblingGate.parsePsOutput(output)
        #expect(entries.count == 2)
        #expect(entries[0].pid == 57122)
        #expect(entries[0].elapsed == "06:39:12")
        #expect(entries[0].commandLine == "/usr/local/bin/cupertino save --docs")
        #expect(entries[1].pid == 90624)
        #expect(entries[1].elapsed == "00:01:23")
    }

    @Test("Lines without three whitespace-separated columns are dropped")
    func skipsMalformed() {
        let output = """
        57122 06:39:12 /usr/local/bin/cupertino save
        garbage line
        90624 00:01:23 /opt/homebrew/bin/cupertino save --packages
        """
        let entries = SaveSiblingGate.parsePsOutput(output)
        #expect(entries.count == 2)
        #expect(entries.map(\.pid) == [57122, 90624])
    }

    @Test("Empty output → empty entries")
    func emptyOutput() {
        #expect(SaveSiblingGate.parsePsOutput("").isEmpty)
    }
}

// MARK: - procargs2 parser

@Suite("SaveSiblingGate.parseProcargs2")
struct ParseProcargs2Tests {
    /// Build a synthetic `KERN_PROCARGS2` buffer for a process with
    /// the given exec_path and argv. Mirrors the xnu layout
    /// documented in `SaveSiblingGate.parseProcargs2`.
    private func makeBuffer(execPath: String, argv: [String]) -> [UInt8] {
        var bytes: [UInt8] = []

        // argc as host-endian Int32
        var argc = Int32(argv.count)
        withUnsafeBytes(of: &argc) { ptr in
            bytes.append(contentsOf: ptr)
        }

        bytes.append(contentsOf: Array(execPath.utf8))
        bytes.append(0)
        // a couple of alignment NUL bytes
        bytes.append(0)
        bytes.append(0)

        for arg in argv {
            bytes.append(contentsOf: Array(arg.utf8))
            bytes.append(0)
        }
        // envp is appended too in real buffers; the parser stops at
        // argc strings so an extra envp string here is fine.
        bytes.append(contentsOf: Array("PATH=/usr/bin".utf8))
        bytes.append(0)
        return bytes
    }

    @Test("Round-trip: synthesised buffer → original argv")
    func roundTrip() {
        let argv = ["/usr/local/bin/cupertino", "save", "--docs", "--yes"]
        let buf = makeBuffer(execPath: "/usr/local/bin/cupertino", argv: argv)
        let parsed = SaveSiblingGate.parseProcargs2(buf)
        #expect(parsed == argv)
    }

    @Test("Single-arg argv")
    func singleArg() {
        let argv = ["/bin/ps"]
        let buf = makeBuffer(execPath: "/bin/ps", argv: argv)
        let parsed = SaveSiblingGate.parseProcargs2(buf)
        #expect(parsed == argv)
    }

    @Test("Too-small buffer returns nil")
    func tooSmall() {
        #expect(SaveSiblingGate.parseProcargs2([1, 2, 3]) == nil)
    }

    @Test("argc=0 returns nil (sentinel for empty / corrupted)")
    func zeroArgc() {
        var bytes: [UInt8] = []
        var argc: Int32 = 0
        withUnsafeBytes(of: &argc) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array("/bin/ps".utf8))
        bytes.append(0)
        #expect(SaveSiblingGate.parseProcargs2(bytes) == nil)
    }
}
