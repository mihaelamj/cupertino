import Foundation

// MARK: - URL Extension for Tilde Expansion

extension URL {
    /// Expand tilde (~) in file paths.
    ///
    /// Detects the `~` anywhere in `path`, not just at the start. This matters
    /// because constructing a `URL(fileURLWithPath: "~/foo.db")` resolves the
    /// relative path against the current working directory at construction
    /// time, so by the time we read `.path` the value is already
    /// `<cwd>/~/foo.db` and a `hasPrefix("~")` check would miss it (which is
    /// exactly why this expansion silently no-opped under `swift test` / CI,
    /// where cwd differs from where the URL literal was written). We rebuild
    /// from `homeDirectoryForCurrentUser` (a password-database lookup) using
    /// whatever follows the tilde.
    public var expandingTildeInPath: URL {
        guard let tildeRange = path.range(of: "~") else { return self }
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let afterTilde = path[tildeRange.upperBound...].drop(while: { $0 == "/" })
        guard !afterTilde.isEmpty else { return homeDirectory }
        return homeDirectory.appendingPathComponent(String(afterTilde))
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
