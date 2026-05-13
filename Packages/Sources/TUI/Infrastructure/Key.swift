import Foundation

// MARK: - TUI Key

enum Key {
    case arrowUp, arrowDown, arrowLeft, arrowRight
    case pageUp, pageDown
    case homeKey, endKey
    case space, tab, enter, escape
    case char(Character)
    case paste(String)
    case ctrl(Character)
    case deleteKey, backspace
    case unknown
}
