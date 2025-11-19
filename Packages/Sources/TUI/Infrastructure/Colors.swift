import Foundation

enum Colors {
    // Reset
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let italic = "\u{001B}[3m"
    static let underline = "\u{001B}[4m"
    static let invert = "\u{001B}[7m"

    // Foreground colors
    static let black = "\u{001B}[30m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let white = "\u{001B}[37m"
    static let gray = "\u{001B}[90m"

    // Bright foreground colors
    static let brightRed = "\u{001B}[91m"
    static let brightGreen = "\u{001B}[92m"
    static let brightYellow = "\u{001B}[93m"
    static let brightBlue = "\u{001B}[94m"
    static let brightMagenta = "\u{001B}[95m"
    static let brightCyan = "\u{001B}[96m"
    static let brightWhite = "\u{001B}[97m"

    // Status indicators
    static let success = brightGreen + "✓" + reset
    static let failure = brightRed + "✗" + reset
    static let warning = brightYellow + "⚠" + reset
    static let info = brightBlue + "ℹ" + reset
    static let running = brightGreen + "●" + reset
    static let stopped = gray + "○" + reset
    static let selected = brightYellow + "★" + reset
}
