import Foundation

// MARK: - Shell Error

extension Release.Shell {
    enum Error: Swift.Error, CustomStringConvertible {
        case commandFailed(String, String)

        var description: String {
            switch self {
            case .commandFailed(let cmd, let output):
                return "Command failed: \(cmd)\n\(output)"
            }
        }
    }
}
