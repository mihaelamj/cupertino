import Foundation
import Testing

// MARK: - #948 phases 3 / 4 / 5 AST-tool CLI subcommand smoke tests

//
// Black-box smoke for the three remaining AST CLI subcommands:
// search-concurrency, search-conformances, search-generics. Each
// test verifies --help surface + that the required argument is
// enforced. Deeper ranking behaviour is covered by the
// SearchSQLiteTests SQL-path tests.

@Suite("#948 phases 3 / 4 / 5 AST-tool CLI subcommands smoke")
struct Issue948Phase345ASTToolsCLITests {
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

    @Test("search-concurrency --help advertises --pattern + --format options")
    func concurrencyHelpAdvertisesCanonicalOptions() throws {
        let result = try run(["search-concurrency", "--help"])
        #expect(result.exit == 0)
        #expect(result.stdout.contains("search-concurrency"))
        #expect(result.stdout.contains("--pattern"))
        #expect(result.stdout.contains("--format"))
    }

    @Test("search-concurrency without --pattern fails with non-zero exit")
    func concurrencyMissingRequiredArgFails() throws {
        let result = try run(["search-concurrency"])
        #expect(result.exit != 0)
    }

    @Test("search-conformances --help advertises --protocol + --format options")
    func conformancesHelpAdvertisesCanonicalOptions() throws {
        let result = try run(["search-conformances", "--help"])
        #expect(result.exit == 0)
        #expect(result.stdout.contains("search-conformances"))
        #expect(result.stdout.contains("--protocol"))
        #expect(result.stdout.contains("--format"))
    }

    @Test("search-conformances without --protocol fails with non-zero exit")
    func conformancesMissingRequiredArgFails() throws {
        let result = try run(["search-conformances"])
        #expect(result.exit != 0)
    }

    @Test("search-generics --help advertises --constraint + --format options")
    func genericsHelpAdvertisesCanonicalOptions() throws {
        let result = try run(["search-generics", "--help"])
        #expect(result.exit == 0)
        #expect(result.stdout.contains("search-generics"))
        #expect(result.stdout.contains("--constraint"))
        #expect(result.stdout.contains("--format"))
    }

    @Test("search-generics without --constraint fails with non-zero exit")
    func genericsMissingRequiredArgFails() throws {
        let result = try run(["search-generics"])
        #expect(result.exit != 0)
    }
}
