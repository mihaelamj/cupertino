@testable import CLI
import Foundation
import Testing

// Unit coverage for the testable surface of `ServeReaper` (#242).
// The runtime reap loop (kill / proc_pidpath / spawning ps) is exercised
// only by manual / staging verification — this suite covers the pure
// string parsing that decides which processes are reap candidates.

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

    // MARK: - isServeSubcommand

    @Test("identifies serve as the subcommand")
    func recognizesServe() {
        #expect(ServeReaper.isServeSubcommand("/usr/local/bin/cupertino serve"))
        #expect(ServeReaper.isServeSubcommand("/usr/local/bin/cupertino serve --search-db /tmp/x"))
        #expect(ServeReaper.isServeSubcommand("cupertino serve"))
    }

    @Test("rejects non-serve subcommands so save/fetch survive (#242 acceptance)")
    func rejectsOthers() {
        #expect(!ServeReaper.isServeSubcommand("/usr/local/bin/cupertino save"))
        #expect(!ServeReaper.isServeSubcommand("/usr/local/bin/cupertino fetch --type docs"))
        #expect(!ServeReaper.isServeSubcommand("/usr/local/bin/cupertino doctor"))
    }

    @Test("does not match word-prefix collisions (server-foo / serves)")
    func wordBoundary() {
        #expect(!ServeReaper.isServeSubcommand("/usr/local/bin/cupertino server-something"))
        #expect(!ServeReaper.isServeSubcommand("/usr/local/bin/cupertino serves"))
    }

    @Test("rejects bare commands with no subcommand")
    func bareBinary() {
        #expect(!ServeReaper.isServeSubcommand("/usr/local/bin/cupertino"))
        #expect(!ServeReaper.isServeSubcommand(""))
    }

    // MARK: - Path-with-spaces edge cases (codex review on #267)

    @Test("handles binary paths that contain spaces")
    func binaryPathWithSpaces() {
        // Real-world cases the previous implementation got wrong:
        #expect(ServeReaper.isServeSubcommand("/Applications/My Tools/cupertino serve"))
        #expect(ServeReaper.isServeSubcommand("/tmp/My Tools/cupertino serve"))
        #expect(ServeReaper.isServeSubcommand("/Users/me/Dev Builds/cupertino serve"))
        #expect(ServeReaper.isServeSubcommand("/Applications/My App/bin/cupertino serve --x"))
        // Negative: serve missing
        #expect(!ServeReaper.isServeSubcommand("/Applications/My Tools/cupertino save"))
        #expect(!ServeReaper.isServeSubcommand("/Applications/My Tools/cupertino"))
    }

    @Test("handles outer directories named like the binary (cupertino-build / cupertino-suffix)")
    func directoryNameContainsBinaryName() {
        // Anchoring on the LAST occurrence of `cupertino` so a directory
        // earlier in the path that happens to contain the substring does
        // not throw the parser off.
        #expect(ServeReaper.isServeSubcommand("/Volumes/cupertino-build/cupertino serve"))
        #expect(ServeReaper.isServeSubcommand("/Apps/cupertino-suffix/cupertino serve"))
        #expect(ServeReaper.isServeSubcommand("/path/cupertino/cupertino serve"))
        #expect(!ServeReaper.isServeSubcommand("/Volumes/cupertino-build/cupertino save"))
    }
}
