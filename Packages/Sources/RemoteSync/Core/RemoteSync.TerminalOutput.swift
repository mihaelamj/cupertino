import Foundation

// MARK: - Terminal Output

extension RemoteSync {
    /// Protocol for terminal output (allows testing)
    public protocol TerminalOutput: Sendable {
        func write(_ string: String)
        func clearLine()
        func moveCursorUp(_ lines: Int)
    }
}
