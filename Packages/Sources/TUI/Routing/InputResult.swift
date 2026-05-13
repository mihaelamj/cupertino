import Foundation

// MARK: - InputHandler Result

/// Result of input handling - either continue running, quit, or request render
enum InputResult {
    case continueRunning
    case quit
    case render
}
