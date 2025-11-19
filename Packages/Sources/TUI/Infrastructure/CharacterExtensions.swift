import Foundation

extension Character {
    var isPrintable: Bool {
        // Allow letters, numbers, and common symbols for paths and general text input
        isLetter || isNumber || isWhitespace || "/-._~:@".contains(self)
    }
}
