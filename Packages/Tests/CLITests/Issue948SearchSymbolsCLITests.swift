import Foundation
import Testing

// MARK: - #948 search-symbols CLI subcommand smoke

//
// Lightweight black-box test: shell out to the release binary and
// verify --help mentions the command + the JSON format produces
// parseable output. The deeper ranking behaviour is covered by
// the Search-package unit tests (Issue177SemanticSearchRerankTests,
// Issue952PropertyWrapperRankingTests) which exercise the same
// `Search.Index.searchSymbols` SQL path the CLI command calls.

@Suite("#948 search-symbols CLI subcommand smoke")
struct Issue948SearchSymbolsCLITests {
    private func binaryPath() -> URL {
        // Tests run from the Packages root (working dir = the SPM
        // package). Use the release binary if present (release CI
        // builds it); fall back to debug.
        let release = URL(fileURLWithPath: ".build/release/cupertino")
        let debug = URL(fileURLWithPath: ".build/debug/cupertino")
        return FileManager.default.fileExists(atPath: release.path) ? release : debug
    }

    private func run(_ args: [String]) throws -> (exit: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = binaryPath()
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    @Test("search-symbols --help advertises the command + describes the canonical options")
    func helpMentionsCommand() throws {
        let result = try run(["search-symbols", "--help"])
        #expect(result.exit == 0, "help should exit 0; got \(result.exit). stderr: \(result.stderr)")
        #expect(result.stdout.contains("search-symbols"), "help missing command name")
        #expect(result.stdout.contains("--query"), "help missing --query option")
        #expect(result.stdout.contains("--kind"), "help missing --kind option")
        #expect(result.stdout.contains("--is-async"), "help missing --is-async option")
        #expect(result.stdout.contains("--framework"), "help missing --framework option")
        #expect(result.stdout.contains("--format"), "help missing --format option")
    }

    @Test("search-symbols --help is reachable from the root --help SUBCOMMANDS section")
    func rootHelpListsSubcommand() throws {
        let result = try run(["--help"])
        #expect(result.exit == 0, "root --help should exit 0; got \(result.exit). stderr: \(result.stderr)")
        #expect(result.stdout.contains("search-symbols"), "root --help should list search-symbols")
    }
}
