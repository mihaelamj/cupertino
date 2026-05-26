import Foundation

// MARK: - Standard Terminal Output

extension RemoteSync {
    /// Standard terminal output using print
    public struct StandardTerminalOutput: TerminalOutput, Sendable {
        public init() {}

        public func write(_ string: String) {
            print(string)
        }

        public func clearLine() {
            print("\u{1B}[2K\u{1B}[G", terminator: "")
        }

        public func moveCursorUp(_ lines: Int) {
            print("\u{1B}[\(lines)A", terminator: "")
        }
    }
}
