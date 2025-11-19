import Foundation

enum Key {
    case up, down, left, right
    case pageUp, pageDown
    case home, end
    case space, tab, enter, escape
    case char(Character)
    case ctrl(Character)
    case delete, backspace
    case unknown
}

final class Input {
    func readKey() -> Key? {
        var buffer = [UInt8](repeating: 0, count: 8)
        let count = read(STDIN_FILENO, &buffer, 8)

        if count == 1 {
            switch buffer[0] {
            case 27: return .escape
            case 32: return .space
            case 9: return .tab
            case 13: return .enter
            case 127: return .backspace
            case 3: return .ctrl("c")
            case 4: return .ctrl("d")
            case 1...26:
                let char = Character(UnicodeScalar(buffer[0] + 96))
                return .ctrl(char)
            case 65...90, 97...122:
                return .char(Character(UnicodeScalar(buffer[0])))
            case 48...57:
                return .char(Character(UnicodeScalar(buffer[0])))
            case 47: return .char("/")
            default: return .unknown
            }
        }

        // Arrow keys: ESC [ A/B/C/D
        if count >= 3, buffer[0] == 27, buffer[1] == 91 {
            switch buffer[2] {
            case 65: return .up
            case 66: return .down
            case 67: return .right
            case 68: return .left
            case 53: return .pageUp // ESC [ 5 ~
            case 54: return .pageDown // ESC [ 6 ~
            case 72: return .home
            case 70: return .end
            default: return .unknown
            }
        }

        return .unknown
    }
}
