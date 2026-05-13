import Foundation

// MARK: - Shell Helpers

extension Release {
    enum Shell {
        @discardableResult
        static func run(_ command: String, quiet: Bool = false) throws -> String {
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                throw Error.commandFailed(command, output)
            }

            return output
        }

        static func runInteractive(_ command: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw Error.commandFailed(command, "Process exited with code \(process.terminationStatus)")
            }
        }
    }
}
