import Foundation

enum Key {
    case arrowUp, arrowDown, arrowLeft, arrowRight
    case pageUp, pageDown
    case homeKey, endKey
    case space, tab, enter, escape
    case char(Character)
    case ctrl(Character)
    case deleteKey, backspace
    case unknown
}

final class Input {
    func readKey() -> Key? {
        var buffer = [UInt8](repeating: 0, count: 8)
        let count = read(STDIN_FILENO, &buffer, 8)

        if count == 1 {
            return parseSingleByte(buffer[0])
        }

        // Arrow keys and escape sequences: ESC [ A/B/C/D
        if count >= 3, buffer[0] == 27, buffer[1] == 91 {
            return parseEscapeSequence(buffer[2])
        }

        return .unknown
    }

    private func parseSingleByte(_ byte: UInt8) -> Key {
        switch byte {
        case 27: return .escape
        case 32: return .space
        case 9: return .tab
        case 13: return .enter
        case 127: return .backspace
        case 3: return .ctrl("c")
        case 4: return .ctrl("d")
        case 1...26: return parseControlChar(byte)
        case 47, 48...57, 65...90, 97...122: return parseRegularChar(byte)
        default: return .unknown
        }
    }

    private func parseControlChar(_ byte: UInt8) -> Key {
        let char = Character(UnicodeScalar(byte + 96))
        return .ctrl(char)
    }

    private func parseRegularChar(_ byte: UInt8) -> Key {
        .char(Character(UnicodeScalar(byte)))
    }

    private func parseEscapeSequence(_ code: UInt8) -> Key {
        switch code {
        case 65: return .arrowUp
        case 66: return .arrowDown
        case 67: return .arrowRight
        case 68: return .arrowLeft
        case 53: return .pageUp // ESC [ 5 ~
        case 54: return .pageDown // ESC [ 6 ~
        case 72: return .homeKey
        case 70: return .endKey
        default: return .unknown
        }
    }
}
