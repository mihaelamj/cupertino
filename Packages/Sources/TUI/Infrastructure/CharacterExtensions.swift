import Foundation

extension Character {
    var isPrintable: Bool {
        // Allow letters, numbers, and common symbols for paths and general text input
        // Including underscore for directory names like "cupertino_test"
        isLetter || isNumber || isWhitespace || "/-._~:@".contains(self)
    }
}
