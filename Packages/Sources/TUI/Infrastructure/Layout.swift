import Foundation

enum Box {
    // Box drawing characters (UTF-8)
    static let topLeft = "┌"
    static let topRight = "┐"
    static let bottomLeft = "└"
    static let bottomRight = "┘"
    static let horizontal = "─"
    static let vertical = "│"
    static let teeDown = "┬"
    static let teeUp = "┴"
    static let teeRight = "├"
    static let teeLeft = "┤"
    static let cross = "┼"

    static func draw(width: Int, height: Int, title: String? = nil) -> String {
        var result = ""

        // Top border
        result += topLeft
        if let title {
            let titleText = " \(title) "
            let remaining = width - 2 - titleText.count
            result += String(repeating: horizontal, count: remaining / 2)
            result += titleText
            result += String(repeating: horizontal, count: remaining - remaining / 2)
        } else {
            result += String(repeating: horizontal, count: width - 2)
        }
        result += topRight + "\n"

        // Middle (empty lines)
        for _ in 0..<(height - 2) {
            result += vertical + String(repeating: " ", count: width - 2) + vertical + "\n"
        }

        // Bottom border
        result += bottomLeft + String(repeating: horizontal, count: width - 2) + bottomRight + "\n"

        return result
    }

    static func horizontalLine(width: Int, title: String? = nil) -> String {
        var result = teeRight
        if let title {
            let titleText = " \(title) "
            let remaining = width - 2 - titleText.count
            result += String(repeating: horizontal, count: remaining / 2)
            result += titleText
            result += String(repeating: horizontal, count: remaining - remaining / 2)
        } else {
            result += String(repeating: horizontal, count: width - 2)
        }
        result += teeLeft
        return result
    }
}
