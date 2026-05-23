import Foundation
import Testing

// MARK: - #948 phase 2: search-property-wrappers CLI subcommand smoke

//
// Lightweight black-box test: shell out to the release binary and
// verify --help advertises the subcommand. The deeper ranking
// behaviour is covered by Issue952PropertyWrapperRankingTests
// which exercises the same Search.Index.searchPropertyWrappers
// SQL path the CLI command calls.

@Suite("#948 phase 2 search-property-wrappers CLI subcommand smoke")
struct Issue948Phase2SearchPropertyWrappersCLITests {
    private func binaryPath() -> URL {
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

    @Test("search-property-wrappers --help advertises the canonical options")
    func helpMentionsCommand() throws {
        let result = try run(["search-property-wrappers", "--help"])
        #expect(result.exit == 0, "help should exit 0; got \(result.exit). stderr: \(result.stderr)")
        #expect(result.stdout.contains("search-property-wrappers"), "help missing command name")
        #expect(result.stdout.contains("--wrapper"), "help missing required --wrapper option")
        #expect(result.stdout.contains("--framework"), "help missing --framework option")
        #expect(result.stdout.contains("--format"), "help missing --format option")
    }

    @Test("search-property-wrappers without --wrapper fails with non-zero exit")
    func missingRequiredArgFails() throws {
        let result = try run(["search-property-wrappers"])
        #expect(result.exit != 0, "missing --wrapper should fail; got exit \(result.exit)")
    }
}
