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
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"
    static let home = "\(ESC)H"
    static let altScreenOn = "\u{001B}[?1049h"
    static let altScreenOff = "\u{001B}[?1049l"

    // Terminal size
    // Note: nonisolated because ioctl() accesses global POSIX file descriptors
    // which are not thread-safe. This must only be called from main thread.
    nonisolated func getSize() -> (rows: Int, cols: Int) {
        var windowSize = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize) == 0 {
            return (Int(windowSize.ws_row), Int(windowSize.ws_col))
        }
        return (24, 80)
    }

    // Raw mode (no buffering, no echo)
    // Note: nonisolated because tcgetattr/tcsetattr access global terminal state
    // via POSIX file descriptors. Must only be called from main thread.
    nonisolated func enableRawMode() -> termios {
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

    // Note: nonisolated because tcsetattr accesses global terminal state
    nonisolated func disableRawMode(_ original: termios) {
        var orig = original
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
    }

    // Cursor positioning
    func moveTo(row: Int, col: Int) -> String {
        "\(Screen.ESC)\(row);\(col)H"
    }

    // Rendering
    // Note: nonisolated because print() and fflush() access global stdout
    // TUI is inherently single-threaded, so this is safe when called from main thread
    nonisolated func render(_ content: String) {
        // Just print content - clearing is done by caller
        print(content, terminator: "")
        fflush(stdout)
    }

    // Enter/exit alternate screen buffer
    // Note: nonisolated because print() and fflush() access global stdout
    nonisolated func enterAltScreen() {
        print(Screen.altScreenOn, terminator: "")
        fflush(stdout)
    }

    // Note: nonisolated because print() and fflush() access global stdout
    nonisolated func exitAltScreen() {
        print(Screen.altScreenOff, terminator: "")
        fflush(stdout)
    }
}
