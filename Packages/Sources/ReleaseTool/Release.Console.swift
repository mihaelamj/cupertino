import Foundation

// MARK: - Console Output

extension Release {
    enum Console {
        static func info(_ message: String) {
            print(message)
        }

        static func success(_ message: String) {
            print("✅ \(message)")
        }

        static func warning(_ message: String) {
            print("⚠️  \(message)")
        }

        static func error(_ message: String) {
            print("❌ \(message)")
        }

        static func step(_ number: Int, _ message: String) {
            print("\n[\(number)] \(message)")
        }

        static func substep(_ message: String) {
            print("    \(message)")
        }
    }
}
