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

    @Test("Bare 'save' with no scope flag → all three targets (covers pre-#1037 stale in-flight binaries)")
    func bareNoFlagDefaultsToAllThree() {
        // Critic round-9 regression guard. Bare `cupertino save` is
        // a legitimate pre-#1037 invocation that builds all three DBs
        // (and may still be in flight on a brew-upgraded machine).
        // The new post-#1037 binary rejects bare save outright at
        // run-time, but a stale pre-#1037 process can still be in
        // the proc table writing concurrently. The parser must report
        // all-three targets so sibling-detection catches the case.
        let argv = ["/usr/local/bin/cupertino", "save"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .packages, .samples])
    }

    @Test("Pre-#1037 backward compat: --docs only → search.db only")
    func legacyDocsOnly() {
        let argv = ["/usr/local/bin/cupertino", "save", "--docs"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search])
    }

    @Test("Pre-#1037 backward compat: --packages only → packages.db only")
    func legacyPackagesOnly() {
        let argv = ["cupertino", "save", "--packages"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.packages])
    }

    @Test("Pre-#1037 backward compat: --samples only → samples.db only")
    func legacySamplesOnly() {
        let argv = ["cupertino", "save", "--samples"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.samples])
    }

    @Test("Pre-#1037 backward compat: --docs + --samples → search + samples (packages excluded)")
    func legacyDocsAndSamples() {
        let argv = ["cupertino", "save", "--docs", "--samples"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .samples])
    }

    @Test("Pre-#1037 backward compat: --docs --packages --samples → all three explicitly")
    func legacyAllThreeExplicit() {
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

    // MARK: - Post-#1037 per-source surface

    @Test("Post-#1037: `--all` → all three targets")
    func postSplitAllFlag() {
        let argv = ["cupertino", "save", "--all"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .packages, .samples])
    }

    @Test("Post-#1037: `--source apple-docs` → search.db (docs bucket)")
    func postSplitSourceAppleDocs() {
        let argv = ["cupertino", "save", "--source", "apple-docs"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search])
    }

    @Test("Post-#1037: `--source packages` → packages.db only")
    func postSplitSourcePackages() {
        let argv = ["cupertino", "save", "--source", "packages"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.packages])
    }

    @Test("Post-#1037: `--source samples` → both .samples AND .search (one-DB-two-tracks dispatch)")
    func postSplitSourceSamples() {
        // Samples scope fires the Sample.Index pipeline (.samples) AND
        // the docs runner (.search) for SampleCodeSource's FTS rows per
        // the one-DB-two-tracks design.
        let argv = ["cupertino", "save", "--source", "samples"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .samples])
    }

    @Test("Post-#1037: `--source apple-sample-code` aliases to samples (same dispatch as --source samples)")
    func postSplitSourceAppleSampleCodeAlias() {
        let argv = ["cupertino", "save", "--source", "apple-sample-code"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .samples])
    }

    @Test("Post-#1037: equals-form `--source=apple-docs` parses too")
    func postSplitSourceEqualsForm() {
        let argv = ["cupertino", "save", "--source=apple-docs"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search])
    }

    @Test("Post-#1037: multiple `--source` values combine (apple-docs + packages → search + packages, samples excluded)")
    func postSplitMultipleSources() {
        let argv = ["cupertino", "save", "--source", "apple-docs", "--source", "packages"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .packages])
    }

    @Test("Post-#1037: unknown `--source` id ignored (binary's resolver raises; sibling detector tolerates)")
    func postSplitUnknownSourceIDIgnored() {
        // Unknown source id contributes no bucket; the binary's own
        // resolver surfaces the unknown-id error to the user at run
        // time.
        let argv = ["cupertino", "save", "--source", "not-a-real-source"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets.isEmpty)
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

    // MARK: - Critic round-9 regression guards

    @Test("Critic round-9: `--all --source apple-docs` returns empty (real binary mutex-errors)")
    func postSplitAllAndSourceMutex() {
        // Real binary throws ExitCode.failure at
        // resolveSelectedSourceIDs(source:all:) when both flags are
        // present. The sibling-detector returns empty so the gate
        // doesn't spuriously block a legitimate parallel save on
        // behalf of a process that's about to die.
        let argv = ["cupertino", "save", "--all", "--source", "apple-docs"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets.isEmpty)
    }

    @Test("Critic round-9: trailing `--source` with no value contributes no bucket")
    func postSplitTrailingSourceNoValue() {
        // Trailing --source with no value is malformed; no bucket
        // should be set.
        let argv = ["cupertino", "save", "--source"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets.isEmpty)
    }

    @Test("Critic round-9: canonical + alias for the same bucket collapse via Set semantics")
    func postSplitCanonicalAndAliasCollapse() {
        let argv = ["cupertino", "save", "--source", "samples", "--source", "apple-sample-code"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(targets == [.search, .samples])
    }

    @Test("Post-#1037 regression: `--source apple-docs` does NOT spuriously claim packages or samples targets")
    func postSplitNoSpuriousTargets() {
        // Load-bearing for the critic round-8 finding #1: pre-fix the
        // parser saw `--source apple-docs` as unrecognised, missed
        // setting sawScopeFlag, and defaulted to all three targets.
        // Any concurrent `cupertino save --source packages` would then
        // fire the sibling-conflict gate against a process that never
        // touches packages.db.
        let argv = ["cupertino", "save", "--source", "apple-docs"]
        let targets = SaveSiblingGate.parseSaveTargets(argv: argv)
        #expect(!targets.contains(.packages), "apple-docs MUST NOT claim packages target")
        #expect(!targets.contains(.samples), "apple-docs MUST NOT claim samples target")
        #expect(targets == [.search])
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
