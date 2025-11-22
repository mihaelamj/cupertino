import Foundation

// Note: Theme support could be added in the future
// - Allow users to choose between different color schemes
// - Consider adding Claude Code-inspired theme with softer, more professional colors
// - Possible themes: Default, Claude, Solarized, Monokai, Nord
// - Store theme preference in ConfigManager

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

    // Background colors
    static let bgBlack = "\u{001B}[40m"
    static let bgRed = "\u{001B}[41m"
    static let bgGreen = "\u{001B}[42m"
    static let bgYellow = "\u{001B}[43m"
    static let bgBlue = "\u{001B}[44m"
    static let bgMagenta = "\u{001B}[45m"
    static let bgCyan = "\u{001B}[46m"
    static let bgWhite = "\u{001B}[47m"

    // Bright background colors
    static let bgBrightBlack = "\u{001B}[100m"
    static let bgBrightRed = "\u{001B}[101m"
    static let bgBrightGreen = "\u{001B}[102m"
    static let bgBrightYellow = "\u{001B}[103m"
    static let bgBrightBlue = "\u{001B}[104m"
    static let bgBrightMagenta = "\u{001B}[105m"
    static let bgBrightCyan = "\u{001B}[106m"
    static let bgBrightWhite = "\u{001B}[107m"

    // Apple-inspired color palette
    static let appleLightBlue = "\u{001B}[38;5;111m" // Soft sky blue
    static let appleBlue = "\u{001B}[38;5;75m" // Apple iOS blue
    static let appleIndigo = "\u{001B}[38;5;105m" // Indigo
    static let applePurple = "\u{001B}[38;5;141m" // Soft purple
    static let appleOrange = "\u{001B}[38;5;215m" // Warm orange
    static let appleGray = "\u{001B}[38;5;246m" // Neutral gray

    // Apple background colors - using high contrast colors
    static let bgAppleBlue = "\u{001B}[46m" // Cyan background (much more visible)
    static let bgAppleIndigo = "\u{001B}[46m" // Cyan background
    static let bgApplePurple = "\u{001B}[46m" // Cyan background
    static let bgAppleOrange = "\u{001B}[43m" // Yellow background for editing
    static let bgAppleGray = "\u{001B}[100m" // Bright black/gray background
    static let bgAppleLightGray = "\u{001B}[47m" // White background

    // Status indicators
    static let success = brightGreen + "✓" + reset
    static let failure = brightRed + "✗" + reset
    static let warning = brightYellow + "⚠" + reset
    static let info = brightBlue + "ℹ" + reset
    static let running = brightGreen + "●" + reset
    static let stopped = gray + "○" + reset
    static let selected = brightYellow + "★" + reset
}
