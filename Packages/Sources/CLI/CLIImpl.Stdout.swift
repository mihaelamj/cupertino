import Foundation

extension CLIImpl {
    static func writeStdout(_ string: String) {
        var output = string
        if !output.hasSuffix("\n") {
            output.append("\n")
        }
        FileHandle.standardOutput.write(Data(output.utf8))
        fflush(stdout)
    }
}
