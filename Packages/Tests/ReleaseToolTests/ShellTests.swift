@testable import ReleaseTool
import Testing

// MARK: - Release.Shell Tests

@Suite("Release.Shell Execution")
struct ShellTests {
    @Test("Run simple command")
    func runSimpleCommand() throws {
        let output = try Release.Shell.run("echo hello")
        #expect(output == "hello")
    }

    @Test("Run command with spaces")
    func runCommandWithSpaces() throws {
        let output = try Release.Shell.run("echo 'hello world'")
        #expect(output == "hello world")
    }

    @Test("Capture multiline output")
    func captureMultilineOutput() throws {
        let output = try Release.Shell.run("printf 'line1\\nline2'")
        #expect(output == "line1\nline2")
    }

    @Test("Throw on failed command")
    func throwOnFailedCommand() {
        #expect(throws: Release.Shell.Error.self) {
            try Release.Shell.run("exit 1")
        }
    }

    @Test("Throw on command not found")
    func throwOnCommandNotFound() {
        #expect(throws: Release.Shell.Error.self) {
            try Release.Shell.run("nonexistent_command_12345")
        }
    }
}

// MARK: - Release.Shell.Error Tests

@Suite("Release.Shell.Error")
struct ShellErrorTests {
    @Test("Error description includes command")
    func errorDescriptionIncludesCommand() {
        let error = Release.Shell.Error.commandFailed("test command", "error output")
        let description = error.description
        #expect(description.contains("test command"))
        #expect(description.contains("error output"))
    }
}
