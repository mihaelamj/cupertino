@testable import ReleaseTool
import Testing

// MARK: - Shell Tests

@Suite("Shell Execution")
struct ShellTests {
    @Test("Run simple command")
    func runSimpleCommand() throws {
        let output = try Shell.run("echo hello")
        #expect(output == "hello")
    }

    @Test("Run command with spaces")
    func runCommandWithSpaces() throws {
        let output = try Shell.run("echo 'hello world'")
        #expect(output == "hello world")
    }

    @Test("Capture multiline output")
    func captureMultilineOutput() throws {
        let output = try Shell.run("printf 'line1\\nline2'")
        #expect(output == "line1\nline2")
    }

    @Test("Throw on failed command")
    func throwOnFailedCommand() {
        #expect(throws: ShellError.self) {
            try Shell.run("exit 1")
        }
    }

    @Test("Throw on command not found")
    func throwOnCommandNotFound() {
        #expect(throws: ShellError.self) {
            try Shell.run("nonexistent_command_12345")
        }
    }
}

// MARK: - ShellError Tests

@Suite("ShellError")
struct ShellErrorTests {
    @Test("Error description includes command")
    func errorDescriptionIncludesCommand() {
        let error = ShellError.commandFailed("test command", "error output")
        let description = error.description
        #expect(description.contains("test command"))
        #expect(description.contains("error output"))
    }
}
