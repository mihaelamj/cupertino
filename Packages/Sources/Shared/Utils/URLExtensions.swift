import Foundation

// MARK: - URL Extension for Tilde Expansion

extension URL {
    /// Expand tilde (~) in file paths
    public var expandingTildeInPath: URL {
        if path.hasPrefix("~") {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let relativePath = String(path.dropFirst(2)) // Remove "~/"
            return homeDirectory.appendingPathComponent(relativePath)
        }
        return self
    }

    /// Build a `URL` from a string the caller asserts is well-formed.
    ///
    /// Use for URLs constructed from compile-time literals or from internal
    /// constants (e.g. `Shared.Constants.BaseURL.*`) interpolated with
    /// sanitized components.
    ///
    /// - Throws: `URLError(.badURL)` if the string cannot be parsed.
    ///
    /// For truly known-good compile-time literals where `try` is unavailable
    /// (stored properties, default parameters), `try! URL(knownGood:)` is
    /// appropriate. For URLs sourced from external/runtime data, use plain
    /// `URL(string:)` + `guard let` instead.
    public init(knownGood string: String) throws {
        guard let url = URL(string: string) else {
            throw URLError(.badURL, userInfo: [NSURLErrorFailingURLStringErrorKey: string])
        }
        self = url
    }
}
