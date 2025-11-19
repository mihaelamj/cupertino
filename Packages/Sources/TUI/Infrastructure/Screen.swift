import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

actor Screen {
    // ANSI escape codes
    static let ESC = "\u{001B}["
    static let clearScreen = "\(ESC)2J"
    static let hideCursor = "\(ESC)?25l"
    static let showCursor = "\(ESC)?25h"
    static let home = "\(ESC)H"
    static let altScreenOn = "\(ESC)?1049h"
    static let altScreenOff = "\(ESC)?1049l"

    // Terminal size
    func getSize() -> (rows: Int, cols: Int) {
        var windowSize = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize) == 0 {
            return (Int(windowSize.ws_row), Int(windowSize.ws_col))
        }
        return (24, 80)
    }

    // Raw mode (no buffering, no echo)
    func enableRawMode() -> termios {
        var original = termios()
        tcgetattr(STDIN_FILENO, &original)

        var raw = original
        raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~UInt(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~UInt(OPOST)
        raw.c_cflag |= UInt(CS8)

        // Non-blocking read with minimal timeout
        raw.c_cc.16 = 0 // VMIN = 0 (return immediately)
        raw.c_cc.17 = 1 // VTIME = 0.1 seconds

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        return original
    }

    func disableRawMode(_ original: termios) {
        var orig = original
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
    }

    // Cursor positioning
    func moveTo(row: Int, col: Int) -> String {
        "\(Screen.ESC)\(row);\(col)H"
    }

    // Rendering
    func render(_ content: String) {
        print(Screen.clearScreen + Screen.home + content, terminator: "")
        fflush(stdout)
    }

    // Enter/exit alternate screen buffer
    func enterAltScreen() {
        print(Screen.altScreenOn, terminator: "")
        fflush(stdout)
    }

    func exitAltScreen() {
        print(Screen.altScreenOff, terminator: "")
        fflush(stdout)
    }
}
